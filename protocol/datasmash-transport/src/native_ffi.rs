// SPDX-License-Identifier: AGPL-3.0-or-later

//! Bounded synchronous C ABI for the KyProto-native StationConnect data plane.

use super::native::{self, NativeClientProtocols, NativeOptions, NativeServerProtocols};
use super::{
    EndpointConfig, EndpointState, SC_DATASMASH_DROPPED, SC_DATASMASH_ERROR_BUFFER_TOO_SMALL,
    SC_DATASMASH_ERROR_INVALID_ARGUMENT, SC_DATASMASH_ERROR_INVALID_STATE,
    SC_DATASMASH_ERROR_PANIC, SC_DATASMASH_ERROR_RUNTIME, SC_DATASMASH_OK, SC_DATASMASH_TIMEOUT,
    ScDatasmashConfig, catch_result, init_crypto_once, parse_config,
};
use anyhow::{Context, Result, anyhow};
use bytes::{BufMut, Bytes, BytesMut};
use kymux_types::{
    AVPacket, CodecPacket, CodecPacketHeader, DataPacket, InputPacket, MediaPacket,
    MediaPacketHeader,
};
use kynet::Server;
use std::collections::VecDeque;
use std::ffi::c_char;
use std::path::Path;
use std::ptr;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant};

const VIDEO_SEND_CAPACITY: usize = 4;
const VIDEO_RECEIVE_CAPACITY: usize = 16;
const AUDIO_SEND_CAPACITY: usize = 16;
const AUDIO_RECEIVE_CAPACITY: usize = 64;
const INPUT_SEND_CAPACITY: usize = 128;
const INPUT_RECEIVE_CAPACITY: usize = 128;
const DATA_SEND_CAPACITY: usize = 64;
const DATA_RECEIVE_CAPACITY: usize = 64;
const MAX_VIDEO_FRAME_SIZE: usize = 64 * 1024 * 1024;
const MAX_AUDIO_PACKET_SIZE: usize = 64 * 1024;
const MAX_INPUT_PACKET_SIZE: usize = u16::MAX as usize;
const MAX_DATA_PACKET_SIZE: usize = 1024 * 1024;
const VIDEO_METADATA_SIZE: usize = 16;
const VIDEO_FLAG_KEY: u32 = 1;
const VIDEO_CODEC_H264: u32 = u32::from_be_bytes(*b"H264");
const VIDEO_CODEC_HEVC: u32 = u32::from_be_bytes(*b"HEVC");
const AUDIO_CODEC_OPUS: u32 = u32::from_be_bytes(*b"OPUS");

#[derive(Clone)]
struct NativeVideoFrame {
    codec: u32,
    flags: u32,
    frame_number: u64,
    pts: u64,
    host_processing_latency: u16,
    payload: Bytes,
}

#[derive(Clone)]
struct NativeAudioPacket {
    pts: u64,
    frame_samples: u16,
    missing_samples: u32,
    payload: Bytes,
}

#[derive(Clone)]
struct NativeInputPacket {
    type_: u8,
    payload: Bytes,
}

#[derive(Default)]
struct NativeQueues {
    video_send: VecDeque<NativeVideoFrame>,
    video_receive: VecDeque<NativeVideoFrame>,
    audio_send: VecDeque<NativeAudioPacket>,
    audio_receive: VecDeque<NativeAudioPacket>,
    input_send: VecDeque<NativeInputPacket>,
    input_receive: VecDeque<NativeInputPacket>,
    data_send: VecDeque<Bytes>,
    data_receive: VecDeque<Bytes>,
}

#[derive(Default)]
struct NativeStats {
    video_frames_sent: AtomicU64,
    video_bytes_sent: AtomicU64,
    video_frames_received: AtomicU64,
    video_bytes_received: AtomicU64,
    video_send_drops: AtomicU64,
    video_receive_drops: AtomicU64,
    audio_packets_sent: AtomicU64,
    audio_bytes_sent: AtomicU64,
    audio_packets_received: AtomicU64,
    audio_bytes_received: AtomicU64,
    audio_send_drops: AtomicU64,
    audio_receive_drops: AtomicU64,
    input_packets_sent: AtomicU64,
    input_packets_received: AtomicU64,
    data_packets_sent: AtomicU64,
    data_packets_received: AtomicU64,
    quic_rtt_us: AtomicU64,
    quic_packets_lost: AtomicU64,
    kyproto_packets_dropped: AtomicU64,
}

struct NativeStatus {
    state: EndpointState,
    error: String,
}

struct NativeShared {
    status: Mutex<NativeStatus>,
    state_changed: Condvar,
    stop: AtomicBool,
    stop_notify: tokio::sync::Notify,
    queues: Mutex<NativeQueues>,
    send_notify: tokio::sync::Notify,
    video_receive_changed: Condvar,
    audio_receive_changed: Condvar,
    input_receive_changed: Condvar,
    data_receive_changed: Condvar,
    stats: NativeStats,
}

impl NativeShared {
    fn new() -> Self {
        Self {
            status: Mutex::new(NativeStatus {
                state: EndpointState::Idle,
                error: String::new(),
            }),
            state_changed: Condvar::new(),
            stop: AtomicBool::new(false),
            stop_notify: tokio::sync::Notify::new(),
            queues: Mutex::new(NativeQueues::default()),
            send_notify: tokio::sync::Notify::new(),
            video_receive_changed: Condvar::new(),
            audio_receive_changed: Condvar::new(),
            input_receive_changed: Condvar::new(),
            data_receive_changed: Condvar::new(),
            stats: NativeStats::default(),
        }
    }

    fn state(&self) -> EndpointState {
        self.status.lock().unwrap().state
    }

    fn set_state(&self, state: EndpointState) {
        self.status.lock().unwrap().state = state;
        self.state_changed.notify_all();
    }

    fn fail(&self, error: impl ToString) {
        let mut status = self.status.lock().unwrap();
        status.error = error.to_string();
        status.state = EndpointState::Failed;
        drop(status);
        self.notify_all();
    }

    fn notify_all(&self) {
        self.state_changed.notify_all();
        self.video_receive_changed.notify_all();
        self.audio_receive_changed.notify_all();
        self.input_receive_changed.notify_all();
        self.data_receive_changed.notify_all();
        self.stop_notify.notify_waiters();
        self.send_notify.notify_waiters();
    }
}

#[repr(C)]
pub struct ScDatasmashNativeVideoFrameInfo {
    pub struct_size: u32,
    pub codec: u32,
    pub flags: u32,
    pub reserved: u32,
    pub frame_number: u64,
    pub pts: u64,
    pub host_processing_latency: u16,
    pub reserved2: [u8; 6],
}

#[repr(C)]
pub struct ScDatasmashNativeAudioPacketInfo {
    pub struct_size: u32,
    pub frame_samples: u16,
    pub reserved: u16,
    pub missing_samples: u32,
    pub reserved2: u32,
    pub pts: u64,
}

#[repr(C)]
pub struct ScDatasmashNativeStats {
    pub struct_size: u32,
    pub video_frames_sent: u64,
    pub video_bytes_sent: u64,
    pub video_frames_received: u64,
    pub video_bytes_received: u64,
    pub video_send_drops: u64,
    pub video_receive_drops: u64,
    pub audio_packets_sent: u64,
    pub audio_bytes_sent: u64,
    pub audio_packets_received: u64,
    pub audio_bytes_received: u64,
    pub audio_send_drops: u64,
    pub audio_receive_drops: u64,
    pub input_packets_sent: u64,
    pub input_packets_received: u64,
    pub data_packets_sent: u64,
    pub data_packets_received: u64,
    pub quic_rtt_us: u64,
    pub quic_packets_lost: u64,
    pub kyproto_packets_dropped: u64,
}

pub struct ScDatasmashNativeEndpoint {
    config: EndpointConfig,
    mode: u32,
    shared: Arc<NativeShared>,
    worker: Mutex<Option<JoinHandle<()>>>,
}

fn native_options(options: super::RuntimeOptions) -> NativeOptions {
    NativeOptions {
        handshake_timeout: options.handshake_timeout,
        idle_timeout: options.idle_timeout,
        keep_alive_interval: options.keep_alive_interval,
    }
}

fn validate_video_codec(codec: u32) -> bool {
    matches!(codec, VIDEO_CODEC_H264 | VIDEO_CODEC_HEVC)
}

async fn send_video(
    shared: Arc<NativeShared>,
    mut protocol: kymux_types::VideoServerProtocol,
) -> Result<()> {
    let mut active_codec = None;
    loop {
        let notified = shared.send_notify.notified();
        let frame = shared.queues.lock().unwrap().video_send.pop_front();
        if let Some(frame) = frame {
            if active_codec != Some(frame.codec) {
                protocol
                    .send
                    .send(AVPacket::Codec(CodecPacket {
                        header: CodecPacketHeader {
                            codec: frame.codec,
                            rotation: 0,
                            frame_size: 0,
                        },
                    }))
                    .await?;
                active_codec = Some(frame.codec);
            }
            let key = frame.flags & VIDEO_FLAG_KEY != 0;
            if key {
                protocol
                    .send
                    .send(AVPacket::Media(MediaPacket {
                        header: MediaPacketHeader {
                            is_config: true,
                            is_key: true,
                            pts: frame.pts,
                            size: 0,
                        },
                        payload: Bytes::new(),
                    }))
                    .await?;
            }
            let payload_size = frame.payload.len() as u64;
            let mut native_payload =
                BytesMut::with_capacity(VIDEO_METADATA_SIZE + frame.payload.len());
            native_payload.put_u64(frame.frame_number);
            native_payload.put_u16(frame.host_processing_latency);
            native_payload.extend_from_slice(&[0; VIDEO_METADATA_SIZE - 10]);
            native_payload.extend_from_slice(&frame.payload);
            let native_payload = native_payload.freeze();
            protocol
                .send
                .send(AVPacket::Media(MediaPacket {
                    header: MediaPacketHeader {
                        is_config: false,
                        is_key: key,
                        pts: frame.pts,
                        size: native_payload.len() as u32,
                    },
                    payload: native_payload,
                }))
                .await?;
            shared
                .stats
                .video_frames_sent
                .fetch_add(1, Ordering::Relaxed);
            shared
                .stats
                .video_bytes_sent
                .fetch_add(payload_size, Ordering::Relaxed);
            continue;
        }
        if shared.stop.load(Ordering::Acquire) {
            return Ok(());
        }
        notified.await;
    }
}

async fn send_audio(
    shared: Arc<NativeShared>,
    mut protocol: kymux_types::AudioServerProtocol,
) -> Result<()> {
    let mut active_frame_samples = None;
    loop {
        let notified = shared.send_notify.notified();
        let packet = shared.queues.lock().unwrap().audio_send.pop_front();
        if let Some(packet) = packet {
            if active_frame_samples != Some(packet.frame_samples) {
                protocol
                    .send
                    .send(AVPacket::Codec(CodecPacket {
                        header: CodecPacketHeader {
                            codec: AUDIO_CODEC_OPUS,
                            rotation: 0,
                            frame_size: packet.frame_samples,
                        },
                    }))
                    .await?;
                protocol
                    .send
                    .send(AVPacket::Media(MediaPacket {
                        header: MediaPacketHeader {
                            is_config: true,
                            is_key: true,
                            pts: packet.pts,
                            size: 0,
                        },
                        payload: Bytes::new(),
                    }))
                    .await?;
                active_frame_samples = Some(packet.frame_samples);
            }
            let payload_size = packet.payload.len() as u64;
            protocol
                .send
                .send(AVPacket::Media(MediaPacket {
                    header: MediaPacketHeader {
                        is_config: false,
                        is_key: false,
                        pts: packet.pts,
                        size: packet.payload.len() as u32,
                    },
                    payload: packet.payload,
                }))
                .await?;
            shared
                .stats
                .audio_packets_sent
                .fetch_add(1, Ordering::Relaxed);
            shared
                .stats
                .audio_bytes_sent
                .fetch_add(payload_size, Ordering::Relaxed);
            continue;
        }
        if shared.stop.load(Ordering::Acquire) {
            return Ok(());
        }
        notified.await;
    }
}

fn push_video_receive(shared: &NativeShared, frame: NativeVideoFrame) {
    let payload_size = frame.payload.len() as u64;
    let dropped = {
        let mut queues = shared.queues.lock().unwrap();
        let dropped = if queues.video_receive.len() == VIDEO_RECEIVE_CAPACITY {
            queues.video_receive.pop_front();
            true
        } else {
            false
        };
        queues.video_receive.push_back(frame);
        dropped
    };
    if dropped {
        shared
            .stats
            .video_receive_drops
            .fetch_add(1, Ordering::Relaxed);
    }
    shared
        .stats
        .video_frames_received
        .fetch_add(1, Ordering::Relaxed);
    shared
        .stats
        .video_bytes_received
        .fetch_add(payload_size, Ordering::Relaxed);
    shared.video_receive_changed.notify_one();
}

async fn receive_video(
    shared: Arc<NativeShared>,
    mut protocol: kymux_types::VideoClientProtocol,
) -> Result<()> {
    let mut codec = 0;
    while let Some(packet) = protocol.recv.recv().await? {
        match packet {
            AVPacket::Codec(packet) => codec = packet.header.codec,
            AVPacket::Media(packet) if !packet.header.is_config => {
                if packet.payload.len() < VIDEO_METADATA_SIZE {
                    return Err(anyhow!("native video frame metadata is truncated"));
                }
                let frame_number = u64::from_be_bytes(
                    packet.payload[..8]
                        .try_into()
                        .expect("video frame number is exactly eight bytes"),
                );
                let host_processing_latency =
                    u16::from_be_bytes([packet.payload[8], packet.payload[9]]);
                push_video_receive(
                    &shared,
                    NativeVideoFrame {
                        codec,
                        flags: if packet.header.is_key {
                            VIDEO_FLAG_KEY
                        } else {
                            0
                        },
                        frame_number,
                        pts: packet.header.pts,
                        host_processing_latency,
                        payload: packet.payload.slice(VIDEO_METADATA_SIZE..),
                    },
                );
            }
            AVPacket::Media(_) => {}
            AVPacket::Hole(_) => return Err(anyhow!("unexpected hole on KyProto video endpoint")),
        }
    }
    Ok(())
}

fn push_audio_receive(shared: &NativeShared, packet: NativeAudioPacket) {
    let payload_size = packet.payload.len() as u64;
    let dropped = {
        let mut queues = shared.queues.lock().unwrap();
        let dropped = if queues.audio_receive.len() == AUDIO_RECEIVE_CAPACITY {
            queues.audio_receive.pop_front();
            true
        } else {
            false
        };
        queues.audio_receive.push_back(packet);
        dropped
    };
    if dropped {
        shared
            .stats
            .audio_receive_drops
            .fetch_add(1, Ordering::Relaxed);
    }
    shared
        .stats
        .audio_packets_received
        .fetch_add(1, Ordering::Relaxed);
    shared
        .stats
        .audio_bytes_received
        .fetch_add(payload_size, Ordering::Relaxed);
    shared.audio_receive_changed.notify_one();
}

async fn receive_audio(
    shared: Arc<NativeShared>,
    mut protocol: kymux_types::AudioClientProtocol,
) -> Result<()> {
    let mut frame_samples = 0;
    while let Some(packet) = protocol.recv.recv().await? {
        match packet {
            AVPacket::Codec(packet) => frame_samples = packet.header.frame_size,
            AVPacket::Media(packet) if !packet.header.is_config => push_audio_receive(
                &shared,
                NativeAudioPacket {
                    pts: packet.header.pts,
                    frame_samples,
                    missing_samples: 0,
                    payload: packet.payload,
                },
            ),
            AVPacket::Hole(packet) => push_audio_receive(
                &shared,
                NativeAudioPacket {
                    pts: 0,
                    frame_samples,
                    missing_samples: packet.header.missing_audio_samples,
                    payload: Bytes::new(),
                },
            ),
            AVPacket::Media(_) => {}
        }
    }
    Ok(())
}

async fn send_input(
    shared: Arc<NativeShared>,
    mut send: kymux_types::ProtocolSend<InputPacket>,
) -> Result<()> {
    loop {
        let notified = shared.send_notify.notified();
        let packet = shared.queues.lock().unwrap().input_send.pop_front();
        if let Some(packet) = packet {
            send.send(InputPacket {
                type_: packet.type_,
                payload: packet.payload,
            })
            .await?;
            shared
                .stats
                .input_packets_sent
                .fetch_add(1, Ordering::Relaxed);
            continue;
        }
        if shared.stop.load(Ordering::Acquire) {
            return Ok(());
        }
        notified.await;
    }
}

async fn receive_input(
    shared: Arc<NativeShared>,
    mut recv: kymux_types::ProtocolRecv<InputPacket>,
) -> Result<()> {
    while let Some(packet) = recv.recv().await? {
        let depth = {
            let mut queues = shared.queues.lock().unwrap();
            if queues.input_receive.len() == INPUT_RECEIVE_CAPACITY {
                return Err(anyhow!("native input receive queue exhausted"));
            }
            queues.input_receive.push_back(NativeInputPacket {
                type_: packet.type_,
                payload: packet.payload,
            });
            queues.input_receive.len()
        };
        debug_assert!(depth <= INPUT_RECEIVE_CAPACITY);
        shared
            .stats
            .input_packets_received
            .fetch_add(1, Ordering::Relaxed);
        shared.input_receive_changed.notify_one();
    }
    Ok(())
}

async fn send_data(
    shared: Arc<NativeShared>,
    mut send: kymux_types::ProtocolSend<DataPacket>,
) -> Result<()> {
    loop {
        let notified = shared.send_notify.notified();
        let payload = shared.queues.lock().unwrap().data_send.pop_front();
        if let Some(payload) = payload {
            send.send(DataPacket { payload }).await?;
            shared
                .stats
                .data_packets_sent
                .fetch_add(1, Ordering::Relaxed);
            continue;
        }
        if shared.stop.load(Ordering::Acquire) {
            return Ok(());
        }
        notified.await;
    }
}

async fn receive_data(
    shared: Arc<NativeShared>,
    mut recv: kymux_types::ProtocolRecv<DataPacket>,
) -> Result<()> {
    while let Some(packet) = recv.recv().await? {
        {
            let mut queues = shared.queues.lock().unwrap();
            if queues.data_receive.len() == DATA_RECEIVE_CAPACITY {
                return Err(anyhow!("native reliable data receive queue exhausted"));
            }
            queues.data_receive.push_back(packet.payload);
        }
        shared
            .stats
            .data_packets_received
            .fetch_add(1, Ordering::Relaxed);
        shared.data_receive_changed.notify_one();
    }
    Ok(())
}

async fn sample_stats(
    shared: Arc<NativeShared>,
    provider: kyproto::KyProtoStatsProvider,
) -> Result<()> {
    let mut interval = tokio::time::interval(Duration::from_secs(1));
    loop {
        interval.tick().await;
        if shared.stop.load(Ordering::Acquire) {
            return Ok(());
        }
        let connection = provider.connection_stats().await;
        let protocol = provider.protocol_stats();
        shared.stats.quic_rtt_us.store(
            connection
                .rtt
                .map(|value| value.as_micros() as u64)
                .unwrap_or_default(),
            Ordering::Relaxed,
        );
        shared.stats.quic_packets_lost.store(
            connection.packets_lost.unwrap_or_default(),
            Ordering::Relaxed,
        );
        shared.stats.kyproto_packets_dropped.store(
            protocol.dropped_packets.unwrap_or_default(),
            Ordering::Relaxed,
        );
    }
}

async fn hold_server(shared: Arc<NativeShared>, protocols: NativeServerProtocols) -> Result<()> {
    let stats_provider = protocols.connection().stats_provider();
    let (connection, video, audio, input, data) = protocols.into_parts();
    let mut video = Box::pin(send_video(shared.clone(), video));
    let mut audio = Box::pin(send_audio(shared.clone(), audio));
    let mut input = Box::pin(receive_input(shared.clone(), input.recv));
    let mut data_send = Box::pin(send_data(shared.clone(), data.send));
    let mut data_receive = Box::pin(receive_data(shared.clone(), data.recv));
    let mut stats = Box::pin(sample_stats(shared.clone(), stats_provider));
    shared.set_state(EndpointState::Ready);
    tokio::select! {
        _ = shared.stop_notify.notified() => Ok(()),
        result = &mut video => result.context("native video sender failed"),
        result = &mut audio => result.context("native audio sender failed"),
        result = &mut input => result.context("native input receiver failed"),
        result = &mut data_send => result.context("native data sender failed"),
        result = &mut data_receive => result.context("native data receiver failed"),
        result = &mut stats => result.context("native stats sampler failed"),
        result = connection.closed() => result.context("native KyProto connection closed"),
    }
}

async fn hold_client(shared: Arc<NativeShared>, protocols: NativeClientProtocols) -> Result<()> {
    let stats_provider = protocols.connection().stats_provider();
    let (connection, video, audio, input, data) = protocols.into_parts();
    let mut video = Box::pin(receive_video(shared.clone(), video));
    let mut audio = Box::pin(receive_audio(shared.clone(), audio));
    let mut input = Box::pin(send_input(shared.clone(), input.send));
    let mut data_send = Box::pin(send_data(shared.clone(), data.send));
    let mut data_receive = Box::pin(receive_data(shared.clone(), data.recv));
    let mut stats = Box::pin(sample_stats(shared.clone(), stats_provider));
    shared.set_state(EndpointState::Ready);
    tokio::select! {
        _ = shared.stop_notify.notified() => Ok(()),
        result = &mut video => result.context("native video receiver failed"),
        result = &mut audio => result.context("native audio receiver failed"),
        result = &mut input => result.context("native input sender failed"),
        result = &mut data_send => result.context("native data sender failed"),
        result = &mut data_receive => result.context("native data receiver failed"),
        result = &mut stats => result.context("native stats sampler failed"),
        result = connection.closed() => result.context("native KyProto connection closed"),
    }
}

async fn run_server(
    shared: Arc<NativeShared>,
    bind_address: std::net::SocketAddr,
    certificate_path: &Path,
    private_key_path: &Path,
    session_token: &str,
    options: super::RuntimeOptions,
) -> Result<()> {
    let certificate = kynet::cert::load_cert_from_pem_file(certificate_path).await?;
    let private_key = kynet::cert::load_private_key_from_pem_file(private_key_path).await?;
    let server_options = kynet::common::CommonServerOptions {
        max_idle_timeout: Some(options.idle_timeout),
        keep_alive_interval: Some(options.keep_alive_interval),
    };
    let server = kynet::Connection::start_server_on_addr(
        bind_address,
        vec![certificate],
        private_key,
        &server_options,
    )?;
    let protocols = native::accept_server(&server, session_token, native_options(options)).await?;
    let result = hold_server(shared, protocols).await;
    server.close(0, "StationConnect native endpoint stopping");
    result
}

async fn run_client(
    shared: Arc<NativeShared>,
    remote_address: std::net::SocketAddr,
    server_name: &str,
    certificate_sha256: &str,
    session_token: &str,
    options: super::RuntimeOptions,
) -> Result<()> {
    let protocols = native::connect_client(
        remote_address,
        server_name,
        certificate_sha256,
        session_token,
        native_options(options),
    )
    .await?;
    hold_client(shared, protocols).await
}

fn worker(config: EndpointConfig, shared: Arc<NativeShared>) {
    init_crypto_once();
    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .worker_threads(4)
        .thread_name("sc-kyproto")
        .build()
    {
        Ok(runtime) => runtime,
        Err(error) => {
            shared.fail(format!("failed to create native KyProto runtime: {error}"));
            return;
        }
    };
    let result = runtime.block_on(async {
        match config {
            EndpointConfig::Server {
                bind_address,
                certificate_path,
                private_key_path,
                session_token,
                options,
            } => {
                run_server(
                    shared.clone(),
                    bind_address,
                    &certificate_path,
                    &private_key_path,
                    &session_token,
                    options,
                )
                .await
            }
            EndpointConfig::Client {
                remote_address,
                server_name,
                certificate_sha256,
                session_token,
                options,
            } => {
                run_client(
                    shared.clone(),
                    remote_address,
                    &server_name,
                    &certificate_sha256,
                    &session_token,
                    options,
                )
                .await
            }
        }
    });
    if shared.stop.load(Ordering::Acquire) {
        shared.set_state(EndpointState::Stopped);
    } else if let Err(error) = result {
        shared.fail(error);
    } else {
        shared.set_state(EndpointState::Stopped);
    }
}

fn enqueue_replaceable<T>(queue: &mut VecDeque<T>, capacity: usize, value: T) -> bool {
    let dropped = if queue.len() == capacity {
        queue.pop_front();
        true
    } else {
        false
    };
    queue.push_back(value);
    dropped
}

fn wait_for_state(shared: &NativeShared, timeout: Duration) -> EndpointState {
    let deadline = Instant::now() + timeout;
    let mut status = shared.status.lock().unwrap();
    while matches!(status.state, EndpointState::Idle | EndpointState::Starting) {
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            break;
        }
        let result = shared
            .state_changed
            .wait_timeout(status, remaining)
            .unwrap();
        status = result.0;
        if result.1.timed_out() {
            break;
        }
    }
    status.state
}

fn copy_bytes_out(
    payload: &Bytes,
    destination: *mut u8,
    capacity: usize,
    size_out: *mut usize,
) -> i32 {
    if size_out.is_null() {
        return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
    }
    unsafe { *size_out = payload.len() };
    if payload.len() > capacity {
        return SC_DATASMASH_ERROR_BUFFER_TOO_SMALL;
    }
    if !payload.is_empty() {
        if destination.is_null() {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        }
        unsafe { ptr::copy_nonoverlapping(payload.as_ptr(), destination, payload.len()) };
    }
    SC_DATASMASH_OK
}

fn wait_pop<T>(
    shared: &NativeShared,
    changed: &Condvar,
    timeout: Duration,
    pop: impl Fn(&mut NativeQueues) -> Option<T>,
) -> Option<T> {
    let deadline = Instant::now() + timeout;
    let mut queues = shared.queues.lock().unwrap();
    loop {
        if let Some(value) = pop(&mut queues) {
            return Some(value);
        }
        if shared.stop.load(Ordering::Acquire)
            || matches!(
                shared.state(),
                EndpointState::Failed | EndpointState::Stopped
            )
        {
            return None;
        }
        let remaining = deadline.saturating_duration_since(Instant::now());
        if remaining.is_zero() {
            return None;
        }
        let result = changed.wait_timeout(queues, remaining).unwrap();
        queues = result.0;
        if result.1.timed_out() {
            return None;
        }
    }
}

/// # Safety
/// `config` and `endpoint_out` must reference valid C objects for this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_endpoint_create(
    config: *const ScDatasmashConfig,
    endpoint_out: *mut *mut ScDatasmashNativeEndpoint,
) -> i32 {
    catch_result(|| {
        if endpoint_out.is_null() {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        }
        unsafe { *endpoint_out = ptr::null_mut() };
        let config = match unsafe { parse_config(config) } {
            Ok(config) => config,
            Err(_) => return SC_DATASMASH_ERROR_INVALID_ARGUMENT,
        };
        let mode = match &config {
            EndpointConfig::Server { .. } => 1,
            EndpointConfig::Client { .. } => 2,
        };
        let endpoint = Box::new(ScDatasmashNativeEndpoint {
            config,
            mode,
            shared: Arc::new(NativeShared::new()),
            worker: Mutex::new(None),
        });
        unsafe { *endpoint_out = Box::into_raw(endpoint) };
        SC_DATASMASH_OK
    })
}

/// # Safety
/// `endpoint` must be null or a live endpoint returned by the create function.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_endpoint_start(
    endpoint: *mut ScDatasmashNativeEndpoint,
) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        if endpoint.shared.state() != EndpointState::Idle {
            return SC_DATASMASH_ERROR_INVALID_STATE;
        }
        endpoint.shared.set_state(EndpointState::Starting);
        let config = endpoint.config.clone();
        let shared = endpoint.shared.clone();
        let worker = std::thread::Builder::new()
            .name("sc-kyproto-main".to_owned())
            .spawn(move || worker(config, shared));
        match worker {
            Ok(worker) => {
                *endpoint.worker.lock().unwrap() = Some(worker);
                SC_DATASMASH_OK
            }
            Err(error) => {
                endpoint.shared.fail(error);
                SC_DATASMASH_ERROR_RUNTIME
            }
        }
    })
}

/// # Safety
/// `endpoint` must be null or a live endpoint returned by the create function.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_endpoint_wait_ready(
    endpoint: *mut ScDatasmashNativeEndpoint,
    timeout_ms: u32,
) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        match wait_for_state(&endpoint.shared, Duration::from_millis(timeout_ms.into())) {
            EndpointState::Ready => SC_DATASMASH_OK,
            EndpointState::Failed => SC_DATASMASH_ERROR_RUNTIME,
            EndpointState::Stopped | EndpointState::Stopping => SC_DATASMASH_ERROR_INVALID_STATE,
            _ => SC_DATASMASH_TIMEOUT,
        }
    })
}

/// # Safety
/// `endpoint` must be null or a live endpoint returned by the create function.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_endpoint_state(
    endpoint: *const ScDatasmashNativeEndpoint,
) -> u32 {
    if endpoint.is_null() {
        EndpointState::Invalid as u32
    } else {
        unsafe { (*endpoint).shared.state() as u32 }
    }
}

/// # Safety
/// All non-null pointers must remain valid for the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_video_send(
    endpoint: *mut ScDatasmashNativeEndpoint,
    info: *const ScDatasmashNativeVideoFrameInfo,
    payload: *const u8,
    payload_size: usize,
) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        let Some(info) = (unsafe { info.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        if endpoint.mode != 1
            || endpoint.shared.state() != EndpointState::Ready
            || info.struct_size as usize != std::mem::size_of::<ScDatasmashNativeVideoFrameInfo>()
            || !validate_video_codec(info.codec)
            || info.flags & !VIDEO_FLAG_KEY != 0
            || payload.is_null()
            || !(1..=MAX_VIDEO_FRAME_SIZE).contains(&payload_size)
        {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        }
        let payload =
            Bytes::copy_from_slice(unsafe { std::slice::from_raw_parts(payload, payload_size) });
        let dropped = enqueue_replaceable(
            &mut endpoint.shared.queues.lock().unwrap().video_send,
            VIDEO_SEND_CAPACITY,
            NativeVideoFrame {
                codec: info.codec,
                flags: info.flags,
                frame_number: info.frame_number,
                pts: info.pts,
                host_processing_latency: info.host_processing_latency,
                payload,
            },
        );
        if dropped {
            endpoint
                .shared
                .stats
                .video_send_drops
                .fetch_add(1, Ordering::Relaxed);
        }
        endpoint.shared.send_notify.notify_one();
        if dropped {
            SC_DATASMASH_DROPPED
        } else {
            SC_DATASMASH_OK
        }
    })
}

/// # Safety
/// All non-null output pointers must name writable storage of the stated size.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_video_receive(
    endpoint: *mut ScDatasmashNativeEndpoint,
    info: *mut ScDatasmashNativeVideoFrameInfo,
    payload: *mut u8,
    payload_capacity: usize,
    payload_size_out: *mut usize,
    timeout_ms: u32,
) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        if endpoint.mode != 2 || info.is_null() || payload_size_out.is_null() {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        }
        let Some(frame) = wait_pop(
            &endpoint.shared,
            &endpoint.shared.video_receive_changed,
            Duration::from_millis(timeout_ms.into()),
            |queues| queues.video_receive.front().cloned(),
        ) else {
            return if endpoint.shared.state() == EndpointState::Failed {
                SC_DATASMASH_ERROR_RUNTIME
            } else {
                SC_DATASMASH_TIMEOUT
            };
        };
        let result = copy_bytes_out(&frame.payload, payload, payload_capacity, payload_size_out);
        if result != SC_DATASMASH_OK {
            return result;
        }
        endpoint
            .shared
            .queues
            .lock()
            .unwrap()
            .video_receive
            .pop_front();
        unsafe {
            *info = ScDatasmashNativeVideoFrameInfo {
                struct_size: std::mem::size_of::<ScDatasmashNativeVideoFrameInfo>() as u32,
                codec: frame.codec,
                flags: frame.flags,
                reserved: 0,
                frame_number: frame.frame_number,
                pts: frame.pts,
                host_processing_latency: frame.host_processing_latency,
                reserved2: [0; 6],
            }
        };
        SC_DATASMASH_OK
    })
}

/// # Safety
/// All non-null pointers must remain valid for the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_audio_send(
    endpoint: *mut ScDatasmashNativeEndpoint,
    info: *const ScDatasmashNativeAudioPacketInfo,
    payload: *const u8,
    payload_size: usize,
) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        let Some(info) = (unsafe { info.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        if endpoint.mode != 1
            || endpoint.shared.state() != EndpointState::Ready
            || info.struct_size as usize != std::mem::size_of::<ScDatasmashNativeAudioPacketInfo>()
            || info.frame_samples == 0
            || info.missing_samples != 0
            || payload.is_null()
            || !(1..=MAX_AUDIO_PACKET_SIZE).contains(&payload_size)
        {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        }
        let payload =
            Bytes::copy_from_slice(unsafe { std::slice::from_raw_parts(payload, payload_size) });
        let dropped = enqueue_replaceable(
            &mut endpoint.shared.queues.lock().unwrap().audio_send,
            AUDIO_SEND_CAPACITY,
            NativeAudioPacket {
                pts: info.pts,
                frame_samples: info.frame_samples,
                missing_samples: 0,
                payload,
            },
        );
        if dropped {
            endpoint
                .shared
                .stats
                .audio_send_drops
                .fetch_add(1, Ordering::Relaxed);
        }
        endpoint.shared.send_notify.notify_one();
        if dropped {
            SC_DATASMASH_DROPPED
        } else {
            SC_DATASMASH_OK
        }
    })
}

/// # Safety
/// All non-null output pointers must name writable storage of the stated size.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_audio_receive(
    endpoint: *mut ScDatasmashNativeEndpoint,
    info: *mut ScDatasmashNativeAudioPacketInfo,
    payload: *mut u8,
    payload_capacity: usize,
    payload_size_out: *mut usize,
    timeout_ms: u32,
) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        if endpoint.mode != 2 || info.is_null() || payload_size_out.is_null() {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        }
        let Some(packet) = wait_pop(
            &endpoint.shared,
            &endpoint.shared.audio_receive_changed,
            Duration::from_millis(timeout_ms.into()),
            |queues| queues.audio_receive.front().cloned(),
        ) else {
            return if endpoint.shared.state() == EndpointState::Failed {
                SC_DATASMASH_ERROR_RUNTIME
            } else {
                SC_DATASMASH_TIMEOUT
            };
        };
        let result = copy_bytes_out(&packet.payload, payload, payload_capacity, payload_size_out);
        if result != SC_DATASMASH_OK {
            return result;
        }
        endpoint
            .shared
            .queues
            .lock()
            .unwrap()
            .audio_receive
            .pop_front();
        unsafe {
            *info = ScDatasmashNativeAudioPacketInfo {
                struct_size: std::mem::size_of::<ScDatasmashNativeAudioPacketInfo>() as u32,
                frame_samples: packet.frame_samples,
                reserved: 0,
                missing_samples: packet.missing_samples,
                reserved2: 0,
                pts: packet.pts,
            }
        };
        SC_DATASMASH_OK
    })
}

/// # Safety
/// All non-null pointers must remain valid for the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_input_send(
    endpoint: *mut ScDatasmashNativeEndpoint,
    type_: u8,
    payload: *const u8,
    payload_size: usize,
) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        if endpoint.mode != 2
            || endpoint.shared.state() != EndpointState::Ready
            || payload.is_null()
            || payload_size > MAX_INPUT_PACKET_SIZE
        {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        }
        let mut queues = endpoint.shared.queues.lock().unwrap();
        if queues.input_send.len() == INPUT_SEND_CAPACITY {
            return SC_DATASMASH_TIMEOUT;
        }
        queues.input_send.push_back(NativeInputPacket {
            type_,
            payload: Bytes::copy_from_slice(unsafe {
                std::slice::from_raw_parts(payload, payload_size)
            }),
        });
        drop(queues);
        endpoint.shared.send_notify.notify_one();
        SC_DATASMASH_OK
    })
}

/// # Safety
/// All non-null output pointers must name writable storage of the stated size.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_input_receive(
    endpoint: *mut ScDatasmashNativeEndpoint,
    type_out: *mut u8,
    payload: *mut u8,
    payload_capacity: usize,
    payload_size_out: *mut usize,
    timeout_ms: u32,
) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        if endpoint.mode != 1 || type_out.is_null() || payload_size_out.is_null() {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        }
        let Some(packet) = wait_pop(
            &endpoint.shared,
            &endpoint.shared.input_receive_changed,
            Duration::from_millis(timeout_ms.into()),
            |queues| queues.input_receive.front().cloned(),
        ) else {
            return if endpoint.shared.state() == EndpointState::Failed {
                SC_DATASMASH_ERROR_RUNTIME
            } else {
                SC_DATASMASH_TIMEOUT
            };
        };
        let result = copy_bytes_out(&packet.payload, payload, payload_capacity, payload_size_out);
        if result != SC_DATASMASH_OK {
            return result;
        }
        endpoint
            .shared
            .queues
            .lock()
            .unwrap()
            .input_receive
            .pop_front();
        unsafe { *type_out = packet.type_ };
        SC_DATASMASH_OK
    })
}

/// # Safety
/// All non-null pointers must remain valid for the duration of this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_data_send(
    endpoint: *mut ScDatasmashNativeEndpoint,
    payload: *const u8,
    payload_size: usize,
) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        if endpoint.shared.state() != EndpointState::Ready
            || payload.is_null()
            || !(1..=MAX_DATA_PACKET_SIZE).contains(&payload_size)
        {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        }
        let mut queues = endpoint.shared.queues.lock().unwrap();
        if queues.data_send.len() == DATA_SEND_CAPACITY {
            return SC_DATASMASH_TIMEOUT;
        }
        queues.data_send.push_back(Bytes::copy_from_slice(unsafe {
            std::slice::from_raw_parts(payload, payload_size)
        }));
        drop(queues);
        endpoint.shared.send_notify.notify_one();
        SC_DATASMASH_OK
    })
}

/// # Safety
/// All non-null output pointers must name writable storage of the stated size.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_data_receive(
    endpoint: *mut ScDatasmashNativeEndpoint,
    payload: *mut u8,
    payload_capacity: usize,
    payload_size_out: *mut usize,
    timeout_ms: u32,
) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        if payload_size_out.is_null() {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        }
        let Some(packet) = wait_pop(
            &endpoint.shared,
            &endpoint.shared.data_receive_changed,
            Duration::from_millis(timeout_ms.into()),
            |queues| queues.data_receive.front().cloned(),
        ) else {
            return if endpoint.shared.state() == EndpointState::Failed {
                SC_DATASMASH_ERROR_RUNTIME
            } else {
                SC_DATASMASH_TIMEOUT
            };
        };
        let result = copy_bytes_out(&packet, payload, payload_capacity, payload_size_out);
        if result != SC_DATASMASH_OK {
            return result;
        }
        endpoint
            .shared
            .queues
            .lock()
            .unwrap()
            .data_receive
            .pop_front();
        SC_DATASMASH_OK
    })
}

/// # Safety
/// `stats` must name writable storage and `endpoint` must remain live.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_endpoint_stats(
    endpoint: *const ScDatasmashNativeEndpoint,
    stats: *mut ScDatasmashNativeStats,
) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        let Some(stats_out) = (unsafe { stats.as_mut() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        if stats_out.struct_size as usize != std::mem::size_of::<ScDatasmashNativeStats>() {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        }
        let stats = &endpoint.shared.stats;
        *stats_out = ScDatasmashNativeStats {
            struct_size: std::mem::size_of::<ScDatasmashNativeStats>() as u32,
            video_frames_sent: stats.video_frames_sent.load(Ordering::Relaxed),
            video_bytes_sent: stats.video_bytes_sent.load(Ordering::Relaxed),
            video_frames_received: stats.video_frames_received.load(Ordering::Relaxed),
            video_bytes_received: stats.video_bytes_received.load(Ordering::Relaxed),
            video_send_drops: stats.video_send_drops.load(Ordering::Relaxed),
            video_receive_drops: stats.video_receive_drops.load(Ordering::Relaxed),
            audio_packets_sent: stats.audio_packets_sent.load(Ordering::Relaxed),
            audio_bytes_sent: stats.audio_bytes_sent.load(Ordering::Relaxed),
            audio_packets_received: stats.audio_packets_received.load(Ordering::Relaxed),
            audio_bytes_received: stats.audio_bytes_received.load(Ordering::Relaxed),
            audio_send_drops: stats.audio_send_drops.load(Ordering::Relaxed),
            audio_receive_drops: stats.audio_receive_drops.load(Ordering::Relaxed),
            input_packets_sent: stats.input_packets_sent.load(Ordering::Relaxed),
            input_packets_received: stats.input_packets_received.load(Ordering::Relaxed),
            data_packets_sent: stats.data_packets_sent.load(Ordering::Relaxed),
            data_packets_received: stats.data_packets_received.load(Ordering::Relaxed),
            quic_rtt_us: stats.quic_rtt_us.load(Ordering::Relaxed),
            quic_packets_lost: stats.quic_packets_lost.load(Ordering::Relaxed),
            kyproto_packets_dropped: stats.kyproto_packets_dropped.load(Ordering::Relaxed),
        };
        SC_DATASMASH_OK
    })
}

fn stop_endpoint(endpoint: &ScDatasmashNativeEndpoint) -> i32 {
    let state = endpoint.shared.state();
    if state == EndpointState::Idle {
        endpoint.shared.set_state(EndpointState::Stopped);
    } else if !matches!(state, EndpointState::Stopped | EndpointState::Failed) {
        endpoint.shared.set_state(EndpointState::Stopping);
        endpoint.shared.stop.store(true, Ordering::Release);
        endpoint.shared.notify_all();
    }
    if let Some(worker) = endpoint.worker.lock().unwrap().take()
        && worker.join().is_err()
    {
        endpoint.shared.fail("native KyProto worker panicked");
        return SC_DATASMASH_ERROR_PANIC;
    }
    if endpoint.shared.state() != EndpointState::Failed {
        endpoint.shared.set_state(EndpointState::Stopped);
    }
    SC_DATASMASH_OK
}

/// # Safety
/// `endpoint` must be null or a live endpoint returned by the create function.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_endpoint_stop(
    endpoint: *mut ScDatasmashNativeEndpoint,
) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        stop_endpoint(endpoint)
    })
}

/// # Safety
/// `endpoint` must be null or a live, not-yet-destroyed endpoint.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_endpoint_destroy(
    endpoint: *mut ScDatasmashNativeEndpoint,
) {
    if endpoint.is_null() {
        return;
    }
    let endpoint = unsafe { Box::from_raw(endpoint) };
    let _ = stop_endpoint(&endpoint);
}

/// # Safety
/// `buffer`, when non-null, must name writable storage of `buffer_size` bytes.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn sc_datasmash_native_endpoint_last_error(
    endpoint: *const ScDatasmashNativeEndpoint,
    buffer: *mut c_char,
    buffer_size: usize,
) -> usize {
    if endpoint.is_null() {
        return 0;
    }
    let error = unsafe { &*endpoint }
        .shared
        .status
        .lock()
        .unwrap()
        .error
        .clone();
    let required = error.len() + 1;
    if !buffer.is_null() && buffer_size != 0 {
        let copy_size = error.len().min(buffer_size - 1);
        unsafe {
            ptr::copy_nonoverlapping(error.as_ptr(), buffer.cast(), copy_size);
            *buffer.add(copy_size) = 0;
        }
    }
    required
}
