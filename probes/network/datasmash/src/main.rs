// SPDX-License-Identifier: AGPL-3.0-or-later
//
// Standalone StationConnect/Kyber QUIC multiplexing qualification probe.

use anyhow::{Context, Result, anyhow, bail};
use bytes::{BufMut, Bytes, BytesMut};
use kynet::{Connection, Server};
use std::collections::HashMap;
use std::env;
use std::net::SocketAddr;
use std::path::Path;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};
use subtle::ConstantTimeEq;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::Mutex;

const PROTOCOL_MAGIC: [u8; 4] = *b"DSM1";
const PROTOCOL_VERSION: u16 = 1;
const DATAGRAM_HEADER_SIZE: usize = 16;
const INPUT_RECORD_SIZE: usize = 16;
const DEFAULT_VIDEO_BITRATE_BPS: u64 = 150_000_000;
const DEFAULT_DURATION_SECS: u64 = 3;
const VIDEO_LANE: u8 = 1;
const AUDIO_LANE: u8 = 2;
const MOTION_LANE: u8 = 3;
#[cfg(feature = "quinn-bbr")]
const CONGESTION_CONTROL: &str = "bbr";
#[cfg(not(feature = "quinn-bbr"))]
const CONGESTION_CONTROL: &str = "cubic";

#[derive(Default)]
struct DatagramCounters {
    video_packets: AtomicU64,
    video_bytes: AtomicU64,
    audio_packets: AtomicU64,
    motion_packets: AtomicU64,
    invalid_packets: AtomicU64,
    blocked_sends: AtomicU64,
    video_sequence_gaps: AtomicU64,
    audio_sequence_gaps: AtomicU64,
    motion_sequence_gaps: AtomicU64,
    stale_datagrams: AtomicU64,
}

#[derive(Debug)]
struct DatagramHeader {
    lane: u8,
    sequence: u64,
}

#[derive(Default)]
struct SequenceTracker {
    latest: Option<u64>,
    gaps: u64,
    stale: u64,
}

impl SequenceTracker {
    fn observe(&mut self, sequence: u64) -> bool {
        let Some(latest) = self.latest else {
            self.latest = Some(sequence);
            return true;
        };
        if sequence <= latest {
            self.stale = self.stale.saturating_add(1);
            return false;
        }
        self.gaps = self
            .gaps
            .saturating_add(sequence.saturating_sub(latest).saturating_sub(1));
        self.latest = Some(sequence);
        true
    }
}

fn usage() -> &'static str {
    "usage:\n  connect-probe-datasmash server <bind-address> <certificate.pem> <key.pem> <token> [duration-seconds] [video-bitrate-bps]\n  connect-probe-datasmash client <server-address> <server-name> <certificate-sha256> <token> [duration-seconds]"
}

fn now_ns() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos()
        .try_into()
        .unwrap_or(u64::MAX)
}

fn make_datagram(lane: u8, sequence: u64, payload_size: usize) -> Bytes {
    let mut packet = BytesMut::with_capacity(DATAGRAM_HEADER_SIZE + payload_size);
    packet.extend_from_slice(&PROTOCOL_MAGIC);
    packet.put_u8(lane);
    packet.put_u8(0);
    packet.put_u16(DATAGRAM_HEADER_SIZE as u16);
    packet.put_u64(sequence);
    packet.resize(DATAGRAM_HEADER_SIZE + payload_size, lane);
    packet.freeze()
}

fn parse_datagram(packet: &Bytes) -> Result<DatagramHeader> {
    if packet.len() < DATAGRAM_HEADER_SIZE {
        bail!("datagram is shorter than the fixed header");
    }
    if packet[..4] != PROTOCOL_MAGIC {
        bail!("datagram magic mismatch");
    }
    let header_size = u16::from_be_bytes([packet[6], packet[7]]) as usize;
    if header_size != DATAGRAM_HEADER_SIZE || header_size > packet.len() {
        bail!("invalid datagram header length");
    }
    Ok(DatagramHeader {
        lane: packet[4],
        sequence: u64::from_be_bytes(packet[8..16].try_into().unwrap()),
    })
}

async fn write_auth(stream: &mut kynet::SendStream, token: &str) -> Result<()> {
    let token_len: u16 = token
        .len()
        .try_into()
        .context("authentication token is too long")?;
    stream.write_all(&PROTOCOL_MAGIC).await?;
    stream.write_all(&PROTOCOL_VERSION.to_be_bytes()).await?;
    stream.write_all(&token_len.to_be_bytes()).await?;
    stream.write_all(token.as_bytes()).await?;
    stream.flush().await?;
    Ok(())
}

async fn read_auth(stream: &mut kynet::RecvStream, expected_token: &str) -> Result<()> {
    let mut header = [0_u8; 8];
    stream.read_exact(&mut header).await?;
    if header[..4] != PROTOCOL_MAGIC {
        bail!("authentication magic mismatch");
    }
    let version = u16::from_be_bytes([header[4], header[5]]);
    if version != PROTOCOL_VERSION {
        bail!("unsupported protocol version {version}");
    }
    let token_len = u16::from_be_bytes([header[6], header[7]]) as usize;
    if token_len == 0 || token_len > 1024 {
        bail!("invalid authentication token length");
    }
    let mut token = vec![0_u8; token_len];
    stream.read_exact(&mut token).await?;
    if token
        .as_slice()
        .ct_eq(expected_token.as_bytes())
        .unwrap_u8()
        != 1
    {
        bail!("authentication token mismatch");
    }
    Ok(())
}

async fn send_video(
    connection: Connection,
    duration: Duration,
    bitrate_bps: u64,
    counters: Arc<DatagramCounters>,
) -> Result<()> {
    let max_datagram_size = connection
        .max_datagram_size()
        .ok_or_else(|| anyhow!("peer did not negotiate QUIC DATAGRAM support"))?;
    if max_datagram_size <= DATAGRAM_HEADER_SIZE {
        bail!("negotiated datagram size {max_datagram_size} is too small");
    }
    let payload_size = (max_datagram_size - DATAGRAM_HEADER_SIZE).min(1_184);
    let packet_size = payload_size + DATAGRAM_HEADER_SIZE;
    let started = Instant::now();
    let mut sequence = 0_u64;
    let mut attempted_bytes = 0_u64;

    while started.elapsed() < duration {
        let target_bytes =
            ((started.elapsed().as_nanos() * bitrate_bps as u128) / 8_000_000_000_u128) as u64;
        if attempted_bytes + packet_size as u64 > target_bytes {
            tokio::time::sleep(Duration::from_micros(100)).await;
            continue;
        }

        let packet = make_datagram(VIDEO_LANE, sequence, payload_size);
        match connection.send_datagram(packet).await {
            Ok(()) => {
                counters.video_packets.fetch_add(1, Ordering::Relaxed);
                counters
                    .video_bytes
                    .fetch_add(packet_size as u64, Ordering::Relaxed);
            }
            Err(_) => {
                counters.blocked_sends.fetch_add(1, Ordering::Relaxed);
            }
        }
        attempted_bytes += packet_size as u64;
        sequence = sequence.wrapping_add(1);
    }
    Ok(())
}

async fn send_audio(connection: Connection, duration: Duration, counters: Arc<DatagramCounters>) {
    let started = Instant::now();
    let mut interval = tokio::time::interval(Duration::from_millis(5));
    let mut sequence = 0_u64;
    while started.elapsed() < duration {
        interval.tick().await;
        match connection
            .send_datagram(make_datagram(AUDIO_LANE, sequence, 256))
            .await
        {
            Ok(()) => {
                counters.audio_packets.fetch_add(1, Ordering::Relaxed);
            }
            Err(_) => {
                counters.blocked_sends.fetch_add(1, Ordering::Relaxed);
            }
        }
        sequence = sequence.wrapping_add(1);
    }
}

async fn receive_server_datagrams(
    connection: Connection,
    stop: Arc<AtomicBool>,
    counters: Arc<DatagramCounters>,
) {
    let mut motion_sequences = SequenceTracker::default();
    while !stop.load(Ordering::Relaxed) {
        let result =
            tokio::time::timeout(Duration::from_millis(100), connection.read_datagram()).await;
        let Ok(Ok(packet)) = result else {
            continue;
        };
        match parse_datagram(&packet) {
            Ok(header) if header.lane == MOTION_LANE => {
                if motion_sequences.observe(header.sequence) {
                    counters.motion_packets.fetch_add(1, Ordering::Relaxed);
                }
            }
            _ => {
                counters.invalid_packets.fetch_add(1, Ordering::Relaxed);
            }
        }
    }
    counters
        .motion_sequence_gaps
        .store(motion_sequences.gaps, Ordering::Relaxed);
    counters
        .stale_datagrams
        .fetch_add(motion_sequences.stale, Ordering::Relaxed);
}

async fn echo_critical_input(
    mut send: kynet::SendStream,
    mut recv: kynet::RecvStream,
) -> Result<u64> {
    let mut count = 0_u64;
    let mut record = [0_u8; INPUT_RECORD_SIZE];
    loop {
        match recv.read_exact(&mut record).await {
            Ok(_) => {
                send.write_all(&record).await?;
                send.flush().await?;
                count += 1;
            }
            Err(error) if error.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(error) => return Err(error.into()),
        }
    }
    Ok(count)
}

async fn run_server(args: &[String]) -> Result<()> {
    if args.len() < 4 || args.len() > 6 {
        bail!(usage());
    }
    let bind_address: SocketAddr = args[0].parse().context("invalid bind address")?;
    let cert_path = Path::new(&args[1]);
    let key_path = Path::new(&args[2]);
    let expected_token = &args[3];
    let duration = Duration::from_secs(
        args.get(4)
            .map(|value| value.parse())
            .transpose()
            .context("invalid duration")?
            .unwrap_or(DEFAULT_DURATION_SECS),
    );
    let bitrate_bps = args
        .get(5)
        .map(|value| value.parse())
        .transpose()
        .context("invalid video bitrate")?
        .unwrap_or(DEFAULT_VIDEO_BITRATE_BPS);

    let certificate = kynet::cert::load_cert_from_pem_file(cert_path).await?;
    let private_key = kynet::cert::load_private_key_from_pem_file(key_path).await?;
    let options = kynet::common::CommonServerOptions {
        max_idle_timeout: Some(Duration::from_secs(10)),
        keep_alive_interval: Some(Duration::from_secs(2)),
    };
    let server =
        Connection::start_server_on_addr(bind_address, vec![certificate], private_key, &options)?;
    println!("status=listening address={bind_address}");

    let connection = server
        .accept()
        .await?
        .ok_or_else(|| anyhow!("QUIC listener closed"))?;
    let (mut input_send, mut input_recv) = connection.accept_bi().await?;
    if let Err(error) = read_auth(&mut input_recv, expected_token).await {
        connection.close(1, "authentication failed");
        return Err(error);
    }
    input_send.write_all(&[0]).await?;
    input_send.flush().await?;

    let counters = Arc::new(DatagramCounters::default());
    let stop = Arc::new(AtomicBool::new(false));
    let receive_task = tokio::spawn(receive_server_datagrams(
        connection.clone(),
        stop.clone(),
        counters.clone(),
    ));
    let echo_task = tokio::spawn(echo_critical_input(input_send, input_recv));
    let video_task = tokio::spawn(send_video(
        connection.clone(),
        duration,
        bitrate_bps,
        counters.clone(),
    ));
    let audio_task = tokio::spawn(send_audio(connection.clone(), duration, counters.clone()));

    video_task.await??;
    audio_task.await?;
    tokio::time::sleep(Duration::from_millis(200)).await;
    stop.store(true, Ordering::Relaxed);
    receive_task.await?;
    let stats = connection.stats().await;
    connection.close(0, "probe complete");
    let critical_input = tokio::time::timeout(Duration::from_secs(1), echo_task)
        .await
        .ok()
        .and_then(|result| result.ok())
        .and_then(|result| result.ok())
        .unwrap_or(0);

    println!(
        "status=complete role=server congestion_control={CONGESTION_CONTROL} video_packets={} video_bytes={} audio_packets={} motion_packets={} critical_input={} blocked_sends={} invalid_packets={} video_sequence_gaps={} audio_sequence_gaps={} motion_sequence_gaps={} stale_datagrams={} quic_rtt_us={} quic_packets_lost={} max_datagram_size={}",
        counters.video_packets.load(Ordering::Relaxed),
        counters.video_bytes.load(Ordering::Relaxed),
        counters.audio_packets.load(Ordering::Relaxed),
        counters.motion_packets.load(Ordering::Relaxed),
        critical_input,
        counters.blocked_sends.load(Ordering::Relaxed),
        counters.invalid_packets.load(Ordering::Relaxed),
        counters.video_sequence_gaps.load(Ordering::Relaxed),
        counters.audio_sequence_gaps.load(Ordering::Relaxed),
        counters.motion_sequence_gaps.load(Ordering::Relaxed),
        counters.stale_datagrams.load(Ordering::Relaxed),
        stats.rtt.map(|value| value.as_micros()).unwrap_or(0),
        stats.packets_lost.unwrap_or(0),
        connection.max_datagram_size().unwrap_or(0),
    );
    Ok(())
}

async fn receive_client_datagrams(
    connection: Connection,
    duration: Duration,
    counters: Arc<DatagramCounters>,
) {
    let deadline = tokio::time::Instant::now() + duration + Duration::from_millis(400);
    let mut video_sequences = SequenceTracker::default();
    let mut audio_sequences = SequenceTracker::default();
    while tokio::time::Instant::now() < deadline {
        let result =
            tokio::time::timeout(Duration::from_millis(100), connection.read_datagram()).await;
        let Ok(Ok(packet)) = result else {
            continue;
        };
        match parse_datagram(&packet) {
            Ok(header) if header.lane == VIDEO_LANE => {
                if video_sequences.observe(header.sequence) {
                    counters.video_packets.fetch_add(1, Ordering::Relaxed);
                    counters
                        .video_bytes
                        .fetch_add(packet.len() as u64, Ordering::Relaxed);
                }
            }
            Ok(header) if header.lane == AUDIO_LANE => {
                if audio_sequences.observe(header.sequence) {
                    counters.audio_packets.fetch_add(1, Ordering::Relaxed);
                }
            }
            _ => {
                counters.invalid_packets.fetch_add(1, Ordering::Relaxed);
            }
        }
    }
    counters
        .video_sequence_gaps
        .store(video_sequences.gaps, Ordering::Relaxed);
    counters
        .audio_sequence_gaps
        .store(audio_sequences.gaps, Ordering::Relaxed);
    counters.stale_datagrams.store(
        video_sequences.stale.saturating_add(audio_sequences.stale),
        Ordering::Relaxed,
    );
}

async fn send_motion(connection: Connection, duration: Duration, counters: Arc<DatagramCounters>) {
    let started = Instant::now();
    let mut interval = tokio::time::interval(Duration::from_millis(1));
    let mut sequence = 0_u64;
    while started.elapsed() < duration {
        interval.tick().await;
        match connection
            .send_datagram(make_datagram(MOTION_LANE, sequence, 24))
            .await
        {
            Ok(()) => {
                counters.motion_packets.fetch_add(1, Ordering::Relaxed);
            }
            Err(_) => {
                counters.blocked_sends.fetch_add(1, Ordering::Relaxed);
            }
        }
        sequence = sequence.wrapping_add(1);
    }
}

async fn run_input_rtt(
    mut send: kynet::SendStream,
    mut recv: kynet::RecvStream,
    duration: Duration,
) -> Result<(u64, u64, u64)> {
    let sent_times = Arc::new(Mutex::new(HashMap::<u64, u64>::new()));
    let samples = Arc::new(Mutex::new(Vec::<u64>::new()));
    let receiver_times = sent_times.clone();
    let receiver_samples = samples.clone();
    let receiver = tokio::spawn(async move {
        let mut record = [0_u8; INPUT_RECORD_SIZE];
        loop {
            match recv.read_exact(&mut record).await {
                Ok(_) => {
                    let sequence = u64::from_be_bytes(record[..8].try_into().unwrap());
                    let sent_ns = u64::from_be_bytes(record[8..].try_into().unwrap());
                    receiver_times.lock().await.remove(&sequence);
                    receiver_samples
                        .lock()
                        .await
                        .push(now_ns().saturating_sub(sent_ns));
                }
                Err(error) if error.kind() == std::io::ErrorKind::UnexpectedEof => break,
                Err(error) => return Err(anyhow!(error)),
            }
        }
        Ok::<(), anyhow::Error>(())
    });

    let started = Instant::now();
    let mut interval = tokio::time::interval(Duration::from_millis(5));
    let mut sequence = 0_u64;
    while started.elapsed() < duration {
        interval.tick().await;
        let timestamp = now_ns();
        let mut record = [0_u8; INPUT_RECORD_SIZE];
        record[..8].copy_from_slice(&sequence.to_be_bytes());
        record[8..].copy_from_slice(&timestamp.to_be_bytes());
        sent_times.lock().await.insert(sequence, timestamp);
        send.write_all(&record).await?;
        send.flush().await?;
        sequence = sequence.wrapping_add(1);
    }
    send.finish().await?;
    tokio::time::timeout(Duration::from_secs(2), receiver).await???;

    let mut values = samples.lock().await.clone();
    if values.is_empty() {
        bail!("no critical-input RTT samples were echoed");
    }
    values.sort_unstable();
    let p50 = values[values.len() / 2];
    let p99 = values[(values.len() * 99 / 100).min(values.len() - 1)];
    Ok((values.len() as u64, p50, p99))
}

async fn run_client(args: &[String]) -> Result<()> {
    if args.len() < 4 || args.len() > 5 {
        bail!(usage());
    }
    let server_address: SocketAddr = args[0].parse().context("invalid server address")?;
    let server_name = &args[1];
    let certificate_hash = &args[2];
    hex::decode(certificate_hash).context("certificate SHA-256 is not valid hex")?;
    let token = &args[3];
    let duration = Duration::from_secs(
        args.get(4)
            .map(|value| value.parse())
            .transpose()
            .context("invalid duration")?
            .unwrap_or(DEFAULT_DURATION_SECS),
    );

    let options = kynet::quinn::QuinnClientOptions {
        max_idle_timeout: Some(Duration::from_secs(10)),
        keep_alive_interval: Some(Duration::from_secs(2)),
        certificate_hash: Some(certificate_hash.clone()),
    };
    let connection = Connection::quinn_connect(server_address, server_name, None, &options).await?;
    let (mut input_send, mut input_recv) = connection.open_bi().await?;
    write_auth(&mut input_send, token).await?;
    let mut auth_status = [1_u8; 1];
    input_recv.read_exact(&mut auth_status).await?;
    if auth_status[0] != 0 {
        bail!("server rejected authentication");
    }

    let counters = Arc::new(DatagramCounters::default());
    let receive_task = tokio::spawn(receive_client_datagrams(
        connection.clone(),
        duration,
        counters.clone(),
    ));
    let motion_task = tokio::spawn(send_motion(connection.clone(), duration, counters.clone()));
    let input_task = tokio::spawn(run_input_rtt(input_send, input_recv, duration));

    motion_task.await?;
    let (input_samples, input_rtt_p50_ns, input_rtt_p99_ns) = input_task.await??;
    receive_task.await?;
    let stats = connection.stats().await;
    connection.close(0, "probe complete");

    let elapsed_seconds = duration.as_secs_f64();
    let received_bitrate =
        counters.video_bytes.load(Ordering::Relaxed) as f64 * 8.0 / elapsed_seconds;
    println!(
        "status=complete role=client congestion_control={CONGESTION_CONTROL} video_packets={} video_bytes={} received_video_bitrate_bps={received_bitrate:.0} audio_packets={} motion_packets={} input_samples={} input_rtt_p50_us={:.1} input_rtt_p99_us={:.1} blocked_sends={} invalid_packets={} video_sequence_gaps={} audio_sequence_gaps={} motion_sequence_gaps={} stale_datagrams={} quic_rtt_us={} quic_packets_lost={} max_datagram_size={}",
        counters.video_packets.load(Ordering::Relaxed),
        counters.video_bytes.load(Ordering::Relaxed),
        counters.audio_packets.load(Ordering::Relaxed),
        counters.motion_packets.load(Ordering::Relaxed),
        input_samples,
        input_rtt_p50_ns as f64 / 1_000.0,
        input_rtt_p99_ns as f64 / 1_000.0,
        counters.blocked_sends.load(Ordering::Relaxed),
        counters.invalid_packets.load(Ordering::Relaxed),
        counters.video_sequence_gaps.load(Ordering::Relaxed),
        counters.audio_sequence_gaps.load(Ordering::Relaxed),
        counters.motion_sequence_gaps.load(Ordering::Relaxed),
        counters.stale_datagrams.load(Ordering::Relaxed),
        stats.rtt.map(|value| value.as_micros()).unwrap_or(0),
        stats.packets_lost.unwrap_or(0),
        connection.max_datagram_size().unwrap_or(0),
    );
    Ok(())
}

#[tokio::main]
async fn main() -> Result<()> {
    kynet::init_crypto();
    let args: Vec<String> = env::args().skip(1).collect();
    let Some((mode, remaining)) = args.split_first() else {
        bail!(usage());
    };
    match mode.as_str() {
        "server" => run_server(remaining).await,
        "client" => run_client(remaining).await,
        _ => bail!(usage()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn datagram_header_round_trip() {
        let packet = make_datagram(MOTION_LANE, 0x0123_4567_89ab_cdef, 32);
        let header = parse_datagram(&packet).unwrap();
        assert_eq!(header.lane, MOTION_LANE);
        assert_eq!(header.sequence, 0x0123_4567_89ab_cdef);
        assert_eq!(packet.len(), DATAGRAM_HEADER_SIZE + 32);
    }

    #[test]
    fn short_datagram_is_rejected() {
        assert!(parse_datagram(&Bytes::from_static(b"DSM1")).is_err());
    }

    #[test]
    fn incorrect_magic_is_rejected() {
        let mut packet = make_datagram(VIDEO_LANE, 1, 0).to_vec();
        packet[0] = b'X';
        assert!(parse_datagram(&Bytes::from(packet)).is_err());
    }

    #[test]
    fn incorrect_header_size_is_rejected() {
        let mut packet = make_datagram(AUDIO_LANE, 2, 0).to_vec();
        packet[6..8].copy_from_slice(&15_u16.to_be_bytes());
        assert!(parse_datagram(&Bytes::from(packet)).is_err());
    }

    #[test]
    fn sequence_tracker_counts_gaps_and_rejects_stale_state() {
        let mut tracker = SequenceTracker::default();

        assert!(tracker.observe(10));
        assert!(tracker.observe(13));
        assert!(!tracker.observe(12));
        assert!(!tracker.observe(13));
        assert!(tracker.observe(14));

        assert_eq!(tracker.latest, Some(14));
        assert_eq!(tracker.gaps, 2);
        assert_eq!(tracker.stale, 2);
    }
}
