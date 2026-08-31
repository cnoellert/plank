// SPDX-License-Identifier: AGPL-3.0-or-later

//! Thin StationConnect ownership boundary around Kyber's native KyProto API.
//!
//! KyProto intentionally remains responsible for endpoint routing, media
//! packetization, RaptorQ, ordering, transport, and protocol statistics.  This
//! module only binds the StationConnect session token and the fixed endpoint
//! manifest negotiated by matching experimental Host and Client builds.

use anyhow::{Context, Result, anyhow, bail};
use kymux_types::{AudioClientProtocol, AudioServerProtocol, DataProtocol, InputProtocol};
use kymux_types::{VideoClientProtocol, VideoServerProtocol};
use kynet::Server;
use kyproto::{AudioProtocol, ClientAuth, Connection, VideoProtocol};
use std::net::SocketAddr;
use std::sync::{Arc, Mutex};
use std::time::Duration;
use subtle::ConstantTimeEq;

pub const VIDEO_ENDPOINT_ID: u16 = 0;
pub const AUDIO_ENDPOINT_ID: u16 = 2;
pub const INPUT_ENDPOINT_ID: u16 = 4;
pub const DATA_ENDPOINT_ID: u16 = 6;
pub const SETUP_DATA_ENDPOINT_ID: u16 = 0;
pub const SETUP_VIDEO_ENDPOINT_ID: u16 = 2;
pub const SETUP_AUDIO_ENDPOINT_ID: u16 = 4;
pub const SETUP_INPUT_ENDPOINT_ID: u16 = 6;

#[derive(Clone, Copy)]
pub struct NativeOptions {
    pub handshake_timeout: Duration,
    pub idle_timeout: Duration,
    pub keep_alive_interval: Duration,
    pub max_udp_payload_size: Option<u16>,
}

pub struct NativeServerProtocols {
    connection: Connection,
    pub video: VideoServerProtocol,
    pub audio: AudioServerProtocol,
    pub input: InputProtocol,
    pub data: DataProtocol,
}

pub struct NativeClientProtocols {
    connection: Connection,
    pub peer_certificate_der: Vec<u8>,
    pub video: VideoClientProtocol,
    pub audio: AudioClientProtocol,
    pub input: InputProtocol,
    pub data: DataProtocol,
}

pub struct NativeSetupServerProtocols {
    connection: Connection,
    pub data: DataProtocol,
}

pub struct NativeSetupClientProtocols {
    connection: Connection,
    pub peer_certificate_der: Vec<u8>,
    pub data: DataProtocol,
}

impl NativeSetupServerProtocols {
    pub fn connection(&self) -> &Connection {
        &self.connection
    }

    pub(crate) fn into_parts(self) -> (Connection, DataProtocol) {
        (self.connection, self.data)
    }
}

impl NativeSetupClientProtocols {
    pub fn connection(&self) -> &Connection {
        &self.connection
    }

    pub(crate) fn into_parts(self) -> (Connection, DataProtocol, Vec<u8>) {
        (self.connection, self.data, self.peer_certificate_der)
    }
}

impl NativeServerProtocols {
    pub fn connection(&self) -> &Connection {
        &self.connection
    }

    pub(crate) fn into_parts(
        self,
    ) -> (
        Connection,
        VideoServerProtocol,
        AudioServerProtocol,
        InputProtocol,
        DataProtocol,
    ) {
        (
            self.connection,
            self.video,
            self.audio,
            self.input,
            self.data,
        )
    }
}

#[derive(Debug)]
struct RecordingCertificateVerifier {
    expected_sha256: Option<Vec<u8>>,
    peer_certificate_der: Arc<Mutex<Option<Vec<u8>>>>,
}

impl rustls::client::danger::ServerCertVerifier for RecordingCertificateVerifier {
    fn verify_server_cert(
        &self,
        end_entity: &rustls::pki_types::CertificateDer<'_>,
        _intermediates: &[rustls::pki_types::CertificateDer<'_>],
        _server_name: &rustls::pki_types::ServerName<'_>,
        _ocsp_response: &[u8],
        _now: rustls::pki_types::UnixTime,
    ) -> Result<rustls::client::danger::ServerCertVerified, rustls::Error> {
        let der = end_entity.as_ref();
        if let Some(expected) = &self.expected_sha256 {
            let actual = ring::digest::digest(&ring::digest::SHA256, der);
            if actual.as_ref().ct_eq(expected).unwrap_u8() != 1 {
                return Err(rustls::Error::General(
                    "StationConnect certificate fingerprint mismatch".to_owned(),
                ));
            }
        }
        *self.peer_certificate_der.lock().unwrap() = Some(der.to_vec());
        Ok(rustls::client::danger::ServerCertVerified::assertion())
    }

    fn verify_tls12_signature(
        &self,
        message: &[u8],
        cert: &rustls::pki_types::CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls12_signature(
            message,
            cert,
            dss,
            &rustls::crypto::ring::default_provider().signature_verification_algorithms,
        )
    }

    fn verify_tls13_signature(
        &self,
        message: &[u8],
        cert: &rustls::pki_types::CertificateDer<'_>,
        dss: &rustls::DigitallySignedStruct,
    ) -> Result<rustls::client::danger::HandshakeSignatureValid, rustls::Error> {
        rustls::crypto::verify_tls13_signature(
            message,
            cert,
            dss,
            &rustls::crypto::ring::default_provider().signature_verification_algorithms,
        )
    }

    fn supported_verify_schemes(&self) -> Vec<rustls::SignatureScheme> {
        rustls::crypto::ring::default_provider()
            .signature_verification_algorithms
            .supported_schemes()
    }
}

impl NativeClientProtocols {
    pub fn connection(&self) -> &Connection {
        &self.connection
    }

    pub(crate) fn into_parts(
        self,
    ) -> (
        Connection,
        VideoClientProtocol,
        AudioClientProtocol,
        InputProtocol,
        DataProtocol,
        Vec<u8>,
    ) {
        (
            self.connection,
            self.video,
            self.audio,
            self.input,
            self.data,
            self.peer_certificate_der,
        )
    }
}

fn verify_endpoint_id(actual: u16, expected: u16, name: &str) -> Result<()> {
    if actual != expected {
        bail!("KyProto allocated {name} endpoint {actual}, expected {expected}");
    }
    Ok(())
}

async fn connect_raw_client(
    remote_address: SocketAddr,
    server_name: &str,
    certificate_sha256: Option<&str>,
    options: NativeOptions,
) -> Result<(kynet::Connection, Vec<u8>)> {
    let expected_sha256 = certificate_sha256
        .map(hex::decode)
        .transpose()
        .context("certificate SHA-256 is not valid hexadecimal")?;
    let peer_certificate_der = Arc::new(Mutex::new(None));
    let verifier = RecordingCertificateVerifier {
        expected_sha256,
        peer_certificate_der: peer_certificate_der.clone(),
    };
    let tls_config = rustls::ClientConfig::builder()
        .dangerous()
        .with_custom_certificate_verifier(Arc::new(verifier))
        .with_no_client_auth();
    let client_options = kynet::quinn::QuinnClientOptions {
        max_idle_timeout: Some(options.idle_timeout),
        keep_alive_interval: Some(options.keep_alive_interval),
        max_udp_payload_size: options.max_udp_payload_size,
        certificate_hash: None,
    };
    let raw_connection = kynet::Connection::quinn_connect(
        remote_address,
        server_name,
        Some(tls_config),
        &client_options,
    )
    .await?;
    let peer_certificate_der = peer_certificate_der
        .lock()
        .unwrap()
        .take()
        .ok_or_else(|| anyhow!("QUIC handshake did not provide a peer certificate"))?;
    Ok((raw_connection, peer_certificate_der))
}

pub async fn accept_server(
    server: &kynet::common::CommonServer,
    expected_token: &str,
    options: NativeOptions,
) -> Result<NativeServerProtocols> {
    let raw_connection = tokio::time::timeout(options.handshake_timeout, server.accept())
        .await
        .context("timed out waiting for native KyProto connection")??
        .ok_or_else(|| anyhow!("native KyProto listener closed"))?;
    let unauthenticated = tokio::time::timeout(
        options.handshake_timeout,
        Connection::accept_with_auth(raw_connection),
    )
    .await
    .context("timed out receiving native KyProto authentication")??;

    if unauthenticated
        .get_auth()
        .token()
        .as_bytes()
        .ct_eq(expected_token.as_bytes())
        .unwrap_u8()
        != 1
    {
        unauthenticated.reject_authentication();
        bail!("native KyProto authentication token mismatch");
    }

    let connection = unauthenticated.accept_authentication().await?;
    let (video_id, video_endpoint) = connection
        .register_video_endpoint(VideoProtocol::UnreliableFec)
        .await?;
    verify_endpoint_id(video_id, VIDEO_ENDPOINT_ID, "video")?;
    let (audio_id, audio_endpoint) = connection
        .register_audio_endpoint(AudioProtocol::UnreliableFec)
        .await?;
    verify_endpoint_id(audio_id, AUDIO_ENDPOINT_ID, "audio")?;
    let (input_id, input_endpoint) = connection.register_input_endpoint().await?;
    verify_endpoint_id(input_id, INPUT_ENDPOINT_ID, "input")?;
    let (data_id, data_endpoint) = connection.register_data_endpoint().await?;
    verify_endpoint_id(data_id, DATA_ENDPOINT_ID, "data")?;

    let ready = async {
        let video = video_endpoint.ready().await?;
        let audio = audio_endpoint.ready().await?;
        let input = input_endpoint.ready().await?;
        let data = data_endpoint.ready().await?;
        Ok::<_, kyproto::ProtocolError>((video, audio, input, data))
    };
    let (video, audio, input, data) = tokio::time::timeout(options.handshake_timeout, ready)
        .await
        .context("timed out starting native KyProto endpoints")??;

    Ok(NativeServerProtocols {
        connection,
        video,
        audio,
        input,
        data,
    })
}

pub async fn connect_client(
    remote_address: SocketAddr,
    server_name: &str,
    certificate_sha256: Option<&str>,
    session_token: &str,
    options: NativeOptions,
) -> Result<NativeClientProtocols> {
    let connect = async {
        let (raw_connection, peer_certificate_der) =
            connect_raw_client(remote_address, server_name, certificate_sha256, options).await?;
        let auth = ClientAuth::new(session_token)?;
        let connection = Connection::connect_with_auth(raw_connection, &auth).await?;

        let video_endpoint =
            connection.connect_video_endpoint(VIDEO_ENDPOINT_ID, VideoProtocol::UnreliableFec)?;
        let audio_endpoint =
            connection.connect_audio_endpoint(AUDIO_ENDPOINT_ID, AudioProtocol::UnreliableFec)?;
        let input_endpoint = connection.connect_input_endpoint(INPUT_ENDPOINT_ID)?;
        let data_endpoint = connection.connect_data_endpoint(DATA_ENDPOINT_ID)?;

        let video = video_endpoint.ready().await?;
        let audio = audio_endpoint.ready().await?;
        let input = input_endpoint.ready().await?;
        let data = data_endpoint.ready().await?;
        Ok::<_, anyhow::Error>(NativeClientProtocols {
            connection,
            peer_certificate_der,
            video,
            audio,
            input,
            data,
        })
    };

    tokio::time::timeout(options.handshake_timeout, connect)
        .await
        .context("timed out establishing native KyProto connection")?
}

pub async fn accept_setup_server(
    server: &kynet::common::CommonServer,
    expected_token: &str,
    options: NativeOptions,
) -> Result<NativeSetupServerProtocols> {
    let raw_connection = tokio::time::timeout(options.handshake_timeout, server.accept())
        .await
        .context("timed out waiting for setup KyProto connection")??
        .ok_or_else(|| anyhow!("setup KyProto listener closed"))?;
    let unauthenticated = tokio::time::timeout(
        options.handshake_timeout,
        Connection::accept_with_auth(raw_connection),
    )
    .await
    .context("timed out receiving setup KyProto marker")??;
    if unauthenticated
        .get_auth()
        .token()
        .as_bytes()
        .ct_eq(expected_token.as_bytes())
        .unwrap_u8()
        != 1
    {
        unauthenticated.reject_authentication();
        bail!("setup KyProto marker mismatch");
    }
    let connection = unauthenticated.accept_authentication().await?;
    let (data_id, data_endpoint) = connection.register_data_endpoint().await?;
    verify_endpoint_id(data_id, SETUP_DATA_ENDPOINT_ID, "setup data")?;
    let data = tokio::time::timeout(options.handshake_timeout, data_endpoint.ready())
        .await
        .context("timed out starting setup data endpoint")??;
    Ok(NativeSetupServerProtocols { connection, data })
}

pub async fn connect_setup_client(
    remote_address: SocketAddr,
    server_name: &str,
    setup_marker: &str,
    options: NativeOptions,
) -> Result<NativeSetupClientProtocols> {
    let connect = async {
        let (raw_connection, peer_certificate_der) =
            connect_raw_client(remote_address, server_name, None, options).await?;
        let auth = ClientAuth::new(setup_marker)?;
        let connection = Connection::connect_with_auth(raw_connection, &auth).await?;
        let data_endpoint = connection.connect_data_endpoint(SETUP_DATA_ENDPOINT_ID)?;
        let data = data_endpoint.ready().await?;
        Ok::<_, anyhow::Error>(NativeSetupClientProtocols {
            connection,
            peer_certificate_der,
            data,
        })
    };
    tokio::time::timeout(options.handshake_timeout, connect)
        .await
        .context("timed out establishing setup KyProto connection")?
}

pub async fn promote_setup_server(
    connection: &Connection,
    options: NativeOptions,
) -> Result<(VideoServerProtocol, AudioServerProtocol, InputProtocol)> {
    let (video_id, video_endpoint) = connection
        .register_video_endpoint(VideoProtocol::UnreliableFec)
        .await?;
    verify_endpoint_id(video_id, SETUP_VIDEO_ENDPOINT_ID, "setup video")?;
    let (audio_id, audio_endpoint) = connection
        .register_audio_endpoint(AudioProtocol::UnreliableFec)
        .await?;
    verify_endpoint_id(audio_id, SETUP_AUDIO_ENDPOINT_ID, "setup audio")?;
    let (input_id, input_endpoint) = connection.register_input_endpoint().await?;
    verify_endpoint_id(input_id, SETUP_INPUT_ENDPOINT_ID, "setup input")?;
    let ready = async {
        let video = video_endpoint.ready().await?;
        let audio = audio_endpoint.ready().await?;
        let input = input_endpoint.ready().await?;
        Ok::<_, kyproto::ProtocolError>((video, audio, input))
    };
    let (video, audio, input) = tokio::time::timeout(options.handshake_timeout, ready)
        .await
        .context("timed out promoting server KyProto endpoints")??;
    Ok((video, audio, input))
}

pub async fn promote_setup_client(
    connection: &Connection,
    options: NativeOptions,
) -> Result<(VideoClientProtocol, AudioClientProtocol, InputProtocol)> {
    let video_endpoint =
        connection.connect_video_endpoint(SETUP_VIDEO_ENDPOINT_ID, VideoProtocol::UnreliableFec)?;
    let audio_endpoint =
        connection.connect_audio_endpoint(SETUP_AUDIO_ENDPOINT_ID, AudioProtocol::UnreliableFec)?;
    let input_endpoint = connection.connect_input_endpoint(SETUP_INPUT_ENDPOINT_ID)?;
    let ready = async {
        let video = video_endpoint.ready().await?;
        let audio = audio_endpoint.ready().await?;
        let input = input_endpoint.ready().await?;
        Ok::<_, kyproto::ProtocolError>((video, audio, input))
    };
    let (video, audio, input) = tokio::time::timeout(options.handshake_timeout, ready)
        .await
        .context("timed out promoting client KyProto endpoints")??;
    Ok((video, audio, input))
}

#[cfg(test)]
mod tests {
    use super::*;
    use bytes::Bytes;
    use kymux_types::{
        AVPacket, CodecPacket, CodecPacketHeader, DataPacket, InputPacket, MediaPacket,
        MediaPacketHeader,
    };
    use std::path::PathBuf;

    fn test_certificate_paths() -> (PathBuf, PathBuf, String) {
        let certificate = std::env::var_os("SC_NATIVE_TEST_CERTIFICATE")
            .map(PathBuf::from)
            .expect("SC_NATIVE_TEST_CERTIFICATE must name the loopback certificate");
        let private_key = std::env::var_os("SC_NATIVE_TEST_PRIVATE_KEY")
            .map(PathBuf::from)
            .expect("SC_NATIVE_TEST_PRIVATE_KEY must name the loopback private key");
        let certificate_sha256 = std::env::var("SC_NATIVE_TEST_CERTIFICATE_SHA256")
            .expect("SC_NATIVE_TEST_CERTIFICATE_SHA256 must contain the DER fingerprint");
        (certificate, private_key, certificate_sha256)
    }

    fn unused_loopback_address() -> SocketAddr {
        let socket = std::net::UdpSocket::bind("127.0.0.1:0")
            .expect("failed to reserve a loopback UDP port");
        let address = socket
            .local_addr()
            .expect("loopback UDP socket has no address");
        drop(socket);
        address
    }

    #[test]
    fn stationconnect_endpoint_manifest_tracks_server_allocation_order() {
        assert_eq!(VIDEO_ENDPOINT_ID, 0);
        assert_eq!(AUDIO_ENDPOINT_ID, VIDEO_ENDPOINT_ID + 2);
        assert_eq!(INPUT_ENDPOINT_ID, AUDIO_ENDPOINT_ID + 2);
        assert_eq!(DATA_ENDPOINT_ID, INPUT_ENDPOINT_ID + 2);
    }

    #[tokio::test(flavor = "multi_thread", worker_threads = 4)]
    #[ignore = "run through scripts/run-datasmash-native-loopback.sh"]
    async fn native_kyproto_round_trip_preserves_all_initial_lanes() {
        crate::init_crypto_once();
        let (certificate_path, private_key_path, certificate_sha256) = test_certificate_paths();
        let certificate = kynet::cert::load_cert_from_pem_file(&certificate_path)
            .await
            .expect("failed to load loopback certificate");
        let private_key = kynet::cert::load_private_key_from_pem_file(&private_key_path)
            .await
            .expect("failed to load loopback private key");
        let address = unused_loopback_address();
        let options = NativeOptions {
            handshake_timeout: Duration::from_secs(5),
            idle_timeout: Duration::from_secs(10),
            keep_alive_interval: Duration::from_secs(1),
            max_udp_payload_size: Some(1344),
        };
        let server_options = kynet::common::CommonServerOptions {
            max_idle_timeout: Some(options.idle_timeout),
            keep_alive_interval: Some(options.keep_alive_interval),
        };
        let server = kynet::Connection::start_server_on_addr(
            address,
            vec![certificate],
            private_key,
            &server_options,
        )
        .expect("failed to start native KyProto loopback server");
        let token = "stationconnect-native-kyproto-loopback";

        let (server_protocols, client_protocols) = tokio::join!(
            accept_server(&server, token, options),
            connect_client(
                address,
                "localhost",
                Some(&certificate_sha256),
                token,
                options,
            ),
        );
        let NativeServerProtocols {
            connection: server_connection,
            video: mut server_video,
            audio: mut server_audio,
            input: mut server_input,
            data: mut server_data,
        } = server_protocols.expect("native KyProto server handshake failed");
        let NativeClientProtocols {
            connection: client_connection,
            video: mut client_video,
            audio: mut client_audio,
            input: mut client_input,
            data: mut client_data,
            peer_certificate_der: _,
        } = client_protocols.expect("native KyProto client handshake failed");

        server_video
            .send
            .send(AVPacket::Codec(CodecPacket {
                header: CodecPacketHeader {
                    codec: u32::from_be_bytes(*b"HEVC"),
                    rotation: 0,
                    frame_size: 0,
                },
            }))
            .await
            .expect("failed to send native video codec packet");
        let video_config_payload = Bytes::from_static(b"annex-b-vps-sps-pps");
        server_video
            .send
            .send(AVPacket::Media(MediaPacket {
                header: MediaPacketHeader {
                    is_config: true,
                    is_key: true,
                    pts: 0,
                    size: video_config_payload.len() as u32,
                },
                payload: video_config_payload.clone(),
            }))
            .await
            .expect("failed to send native video configuration packet");
        let video_payload = Bytes::from(
            (0..192 * 1024)
                .map(|index| ((index * 37 + 11) & 0xff) as u8)
                .collect::<Vec<_>>(),
        );
        server_video
            .send
            .send(AVPacket::Media(MediaPacket {
                header: MediaPacketHeader {
                    is_config: false,
                    is_key: true,
                    pts: 90_000,
                    size: video_payload.len() as u32,
                },
                payload: video_payload.clone(),
            }))
            .await
            .expect("failed to send native RaptorQ video frame");

        let received_video_codec =
            tokio::time::timeout(Duration::from_secs(5), client_video.recv.recv())
                .await
                .expect("native video codec receive timed out")
                .expect("native video codec receive failed")
                .expect("native video codec endpoint closed");
        assert!(matches!(received_video_codec, AVPacket::Codec(_)));
        let received_video_config =
            tokio::time::timeout(Duration::from_secs(5), client_video.recv.recv())
                .await
                .expect("native video configuration receive timed out")
                .expect("native video configuration receive failed")
                .expect("native video endpoint closed before configuration");
        let AVPacket::Media(received_video_config) = received_video_config else {
            panic!("native video endpoint returned a non-media configuration packet");
        };
        assert!(received_video_config.header.is_config);
        assert_eq!(received_video_config.payload, video_config_payload);
        let received_video = tokio::time::timeout(Duration::from_secs(5), client_video.recv.recv())
            .await
            .expect("native video frame receive timed out")
            .expect("native video frame receive failed")
            .expect("native video endpoint closed");
        let AVPacket::Media(received_video) = received_video else {
            panic!("native video endpoint returned a non-media packet");
        };
        assert!(received_video.header.is_key);
        assert_eq!(received_video.header.pts, 90_000);
        assert_eq!(received_video.payload, video_payload);
        let video_protocol_stats = client_connection.protocol_stats();
        assert!(
            video_protocol_stats
                .video_fec_source_symbols
                .unwrap_or_default()
                > 0
        );
        assert_eq!(
            video_protocol_stats
                .video_fec_source_symbols_missing
                .unwrap_or_default(),
            0
        );

        server_audio
            .send
            .send(AVPacket::Codec(CodecPacket {
                header: CodecPacketHeader {
                    codec: u32::from_be_bytes(*b"OPUS"),
                    rotation: 0,
                    frame_size: 960,
                },
            }))
            .await
            .expect("failed to send native audio codec packet");
        let audio_config_payload = Bytes::from_static(b"OpusHead");
        server_audio
            .send
            .send(AVPacket::Media(MediaPacket {
                header: MediaPacketHeader {
                    is_config: true,
                    is_key: true,
                    pts: 0,
                    size: audio_config_payload.len() as u32,
                },
                payload: audio_config_payload.clone(),
            }))
            .await
            .expect("failed to send native audio configuration packet");
        let audio_payload = Bytes::from_static(b"stationconnect-opus-packet");
        server_audio
            .send
            .send(AVPacket::Media(MediaPacket {
                header: MediaPacketHeader {
                    is_config: false,
                    is_key: false,
                    pts: 960,
                    size: audio_payload.len() as u32,
                },
                payload: audio_payload.clone(),
            }))
            .await
            .expect("failed to send native RaptorQ audio packet");
        assert!(matches!(
            tokio::time::timeout(Duration::from_secs(5), client_audio.recv.recv())
                .await
                .expect("native audio codec receive timed out")
                .expect("native audio codec receive failed")
                .expect("native audio endpoint closed"),
            AVPacket::Codec(_)
        ));
        let received_audio_config =
            tokio::time::timeout(Duration::from_secs(5), client_audio.recv.recv())
                .await
                .expect("native audio configuration receive timed out")
                .expect("native audio configuration receive failed")
                .expect("native audio endpoint closed before configuration");
        let AVPacket::Media(received_audio_config) = received_audio_config else {
            panic!("native audio endpoint returned a non-media configuration packet");
        };
        assert!(received_audio_config.header.is_config);
        assert_eq!(received_audio_config.payload, audio_config_payload);
        let received_audio = tokio::time::timeout(Duration::from_secs(5), client_audio.recv.recv())
            .await
            .expect("native audio packet receive timed out")
            .expect("native audio packet receive failed")
            .expect("native audio endpoint closed");
        let AVPacket::Media(received_audio) = received_audio else {
            panic!("native audio endpoint returned a non-media packet");
        };
        assert_eq!(received_audio.payload, audio_payload);

        let input_payload = Bytes::from_static(b"wacom-state-transition");
        client_input
            .send
            .send(InputPacket {
                type_: 7,
                payload: input_payload.clone(),
            })
            .await
            .expect("failed to send native input packet");
        let received_input = tokio::time::timeout(Duration::from_secs(5), server_input.recv.recv())
            .await
            .expect("native input receive timed out")
            .expect("native input receive failed")
            .expect("native input endpoint closed");
        assert_eq!(received_input.type_, 7);
        assert_eq!(received_input.payload, input_payload);

        let client_data_payload = Bytes::from_static(b"client-control");
        client_data
            .send
            .send(DataPacket {
                payload: client_data_payload.clone(),
            })
            .await
            .expect("failed to send native client data packet");
        let received_client_data =
            tokio::time::timeout(Duration::from_secs(5), server_data.recv.recv())
                .await
                .expect("native client data receive timed out")
                .expect("native client data receive failed")
                .expect("native server data endpoint closed");
        assert_eq!(received_client_data.payload, client_data_payload);

        let server_data_payload = Bytes::from_static(b"server-control");
        server_data
            .send
            .send(DataPacket {
                payload: server_data_payload.clone(),
            })
            .await
            .expect("failed to send native server data packet");
        let received_server_data =
            tokio::time::timeout(Duration::from_secs(5), client_data.recv.recv())
                .await
                .expect("native server data receive timed out")
                .expect("native server data receive failed")
                .expect("native client data endpoint closed");
        assert_eq!(received_server_data.payload, server_data_payload);

        let server_stats = server_connection.connection_stats().await;
        let client_stats = client_connection.connection_stats().await;
        assert!(server_stats.rtt.is_some());
        assert!(client_stats.rtt.is_some());
        assert_eq!(
            client_connection
                .protocol_stats()
                .dropped_packets
                .unwrap_or_default(),
            0
        );
        server_connection.close();
        client_connection.close();
        server.close(0, "native KyProto loopback complete");
    }
}
