// SPDX-License-Identifier: AGPL-3.0-or-later

use anyhow::{Context, Result, anyhow, bail};
use kynet::{Connection, Server};
use std::ffi::{CStr, c_char};
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::ptr;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex, Once};
use std::thread::JoinHandle;
use std::time::Duration;
use subtle::ConstantTimeEq;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

pub const PROTOCOL_MAGIC: [u8; 4] = *b"DSM1";
pub const PROTOCOL_VERSION: u16 = 2;
pub const ABI_VERSION: u32 = 1;

const DEFAULT_HANDSHAKE_TIMEOUT_MS: u32 = 10_000;
const DEFAULT_IDLE_TIMEOUT_MS: u32 = 10_000;
const DEFAULT_KEEP_ALIVE_INTERVAL_MS: u32 = 2_000;
const MAX_ADDRESS_LENGTH: usize = 512;
const MAX_SERVER_NAME_LENGTH: usize = 253;
const MAX_PATH_LENGTH: usize = 4_096;
const MAX_TOKEN_LENGTH: usize = 1_024;

pub const SC_DATASMASH_OK: i32 = 0;
pub const SC_DATASMASH_TIMEOUT: i32 = 1;
pub const SC_DATASMASH_ERROR_INVALID_ARGUMENT: i32 = -1;
pub const SC_DATASMASH_ERROR_INVALID_STATE: i32 = -2;
pub const SC_DATASMASH_ERROR_RUNTIME: i32 = -3;
pub const SC_DATASMASH_ERROR_PANIC: i32 = -4;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u8)]
pub enum ConnectionRole {
    Media = 1,
    Interaction = 2,
}

impl ConnectionRole {
    pub fn name(self) -> &'static str {
        match self {
            Self::Media => "media",
            Self::Interaction => "interaction",
        }
    }
}

impl TryFrom<u8> for ConnectionRole {
    type Error = anyhow::Error;

    fn try_from(value: u8) -> Result<Self> {
        match value {
            value if value == Self::Media as u8 => Ok(Self::Media),
            value if value == Self::Interaction as u8 => Ok(Self::Interaction),
            _ => bail!("unknown connection role {value}"),
        }
    }
}

pub async fn write_auth(stream: &mut kynet::SendStream, token: &str, role: u8) -> Result<()> {
    let token_len: u16 = token
        .len()
        .try_into()
        .context("authentication token is too long")?;
    stream.write_all(&PROTOCOL_MAGIC).await?;
    stream.write_all(&PROTOCOL_VERSION.to_be_bytes()).await?;
    stream.write_all(&[role]).await?;
    stream.write_all(&token_len.to_be_bytes()).await?;
    stream.write_all(token.as_bytes()).await?;
    stream.flush().await?;
    Ok(())
}

pub async fn read_auth(
    stream: &mut kynet::RecvStream,
    expected_token: &str,
) -> Result<ConnectionRole> {
    let mut header = [0_u8; 9];
    stream.read_exact(&mut header).await?;
    if header[..4] != PROTOCOL_MAGIC {
        bail!("authentication magic mismatch");
    }
    let version = u16::from_be_bytes([header[4], header[5]]);
    if version != PROTOCOL_VERSION {
        bail!("unsupported protocol version {version}");
    }
    let role = ConnectionRole::try_from(header[6])?;
    let token_len = u16::from_be_bytes([header[7], header[8]]) as usize;
    if token_len == 0 || token_len > MAX_TOKEN_LENGTH {
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
    Ok(role)
}

pub async fn accept_authenticated_candidate(
    server: &kynet::common::CommonServer,
    expected_token: &str,
) -> Result<(
    ConnectionRole,
    Connection,
    kynet::SendStream,
    kynet::RecvStream,
)> {
    let connection = server
        .accept()
        .await?
        .ok_or_else(|| anyhow!("QUIC listener closed"))?;
    let (send, mut recv) = connection.accept_bi().await?;
    let role = match read_auth(&mut recv, expected_token).await {
        Ok(role) => role,
        Err(error) => {
            connection.close(1, "authentication failed");
            return Err(error);
        }
    };
    Ok((role, connection, send, recv))
}

pub async fn connect_with_role_code(
    server_address: SocketAddr,
    server_name: &str,
    options: &kynet::quinn::QuinnClientOptions,
    token: &str,
    role: u8,
    role_name: &str,
) -> Result<(Connection, kynet::SendStream, kynet::RecvStream)> {
    let connection = Connection::quinn_connect(server_address, server_name, None, options).await?;
    let (mut send, mut recv) = connection.open_bi().await?;
    write_auth(&mut send, token, role).await?;
    let mut auth_status = [1_u8; 1];
    recv.read_exact(&mut auth_status).await?;
    if auth_status[0] != 0 {
        connection.close(1, "authentication rejected");
        bail!("server rejected {role_name} authentication");
    }
    Ok((connection, send, recv))
}

pub async fn connect_authenticated(
    server_address: SocketAddr,
    server_name: &str,
    options: &kynet::quinn::QuinnClientOptions,
    token: &str,
    role: ConnectionRole,
) -> Result<(Connection, kynet::SendStream, kynet::RecvStream)> {
    connect_with_role_code(
        server_address,
        server_name,
        options,
        token,
        role as u8,
        role.name(),
    )
    .await
}

fn init_crypto_once() {
    static CRYPTO_INIT: Once = Once::new();
    CRYPTO_INIT.call_once(kynet::init_crypto);
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum EndpointState {
    Invalid = 0,
    Idle = 1,
    Starting = 2,
    Ready = 3,
    Stopping = 4,
    Stopped = 5,
    Failed = 6,
}

#[derive(Clone)]
enum EndpointConfig {
    Server {
        bind_address: SocketAddr,
        certificate_path: PathBuf,
        private_key_path: PathBuf,
        session_token: String,
        options: RuntimeOptions,
    },
    Client {
        remote_address: SocketAddr,
        server_name: String,
        certificate_sha256: String,
        session_token: String,
        options: RuntimeOptions,
    },
}

#[derive(Clone, Copy)]
struct RuntimeOptions {
    handshake_timeout: Duration,
    idle_timeout: Duration,
    keep_alive_interval: Duration,
}

struct SharedStatus {
    state: EndpointState,
    error: String,
}

struct Shared {
    status: Mutex<SharedStatus>,
    changed: Condvar,
    stop: AtomicBool,
    stop_notify: tokio::sync::Notify,
}

impl Shared {
    fn new() -> Self {
        Self {
            status: Mutex::new(SharedStatus {
                state: EndpointState::Idle,
                error: String::new(),
            }),
            changed: Condvar::new(),
            stop: AtomicBool::new(false),
            stop_notify: tokio::sync::Notify::new(),
        }
    }

    fn state(&self) -> EndpointState {
        self.status.lock().unwrap().state
    }

    fn set_state(&self, state: EndpointState) {
        let mut status = self.status.lock().unwrap();
        status.state = state;
        self.changed.notify_all();
    }

    fn fail(&self, error: impl ToString) {
        let mut status = self.status.lock().unwrap();
        status.error = error.to_string();
        status.state = EndpointState::Failed;
        self.changed.notify_all();
    }
}

#[repr(C)]
pub struct ScDatasmashConfig {
    pub struct_size: u32,
    pub abi_version: u32,
    pub mode: u32,
    pub handshake_timeout_ms: u32,
    pub idle_timeout_ms: u32,
    pub keep_alive_interval_ms: u32,
    pub bind_address: *const c_char,
    pub remote_address: *const c_char,
    pub server_name: *const c_char,
    pub certificate_path: *const c_char,
    pub private_key_path: *const c_char,
    pub certificate_sha256: *const c_char,
    pub session_token: *const c_char,
}

pub struct ScDatasmashEndpoint {
    config: EndpointConfig,
    shared: Arc<Shared>,
    worker: Mutex<Option<JoinHandle<()>>>,
}

unsafe fn required_string(value: *const c_char, field: &str, maximum: usize) -> Result<String> {
    if value.is_null() {
        bail!("{field} is required");
    }
    let value = unsafe { CStr::from_ptr(value) };
    let bytes = value.to_bytes();
    if bytes.is_empty() || bytes.len() > maximum {
        bail!("{field} length is invalid");
    }
    Ok(value
        .to_str()
        .with_context(|| format!("{field} is not UTF-8"))?
        .to_owned())
}

fn configured_duration(value_ms: u32, default_ms: u32, field: &str) -> Result<Duration> {
    let value_ms = if value_ms == 0 { default_ms } else { value_ms };
    if !(100..=120_000).contains(&value_ms) {
        bail!("{field} must be between 100 and 120000 milliseconds");
    }
    Ok(Duration::from_millis(u64::from(value_ms)))
}

unsafe fn parse_config(config: *const ScDatasmashConfig) -> Result<EndpointConfig> {
    if config.is_null() {
        bail!("config is required");
    }
    let config = unsafe { &*config };
    if config.struct_size as usize != std::mem::size_of::<ScDatasmashConfig>() {
        bail!("config structure size mismatch");
    }
    if config.abi_version != ABI_VERSION {
        bail!("unsupported ABI version {}", config.abi_version);
    }
    let options = RuntimeOptions {
        handshake_timeout: configured_duration(
            config.handshake_timeout_ms,
            DEFAULT_HANDSHAKE_TIMEOUT_MS,
            "handshake_timeout_ms",
        )?,
        idle_timeout: configured_duration(
            config.idle_timeout_ms,
            DEFAULT_IDLE_TIMEOUT_MS,
            "idle_timeout_ms",
        )?,
        keep_alive_interval: configured_duration(
            config.keep_alive_interval_ms,
            DEFAULT_KEEP_ALIVE_INTERVAL_MS,
            "keep_alive_interval_ms",
        )?,
    };
    if options.keep_alive_interval >= options.idle_timeout {
        bail!("keep_alive_interval_ms must be less than idle_timeout_ms");
    }

    match config.mode {
        1 => {
            let bind_address = unsafe {
                required_string(config.bind_address, "bind_address", MAX_ADDRESS_LENGTH)?
            }
            .parse()
            .context("bind_address is not a socket address")?;
            let certificate_path = PathBuf::from(unsafe {
                required_string(config.certificate_path, "certificate_path", MAX_PATH_LENGTH)?
            });
            let private_key_path = PathBuf::from(unsafe {
                required_string(config.private_key_path, "private_key_path", MAX_PATH_LENGTH)?
            });
            let session_token = unsafe {
                required_string(config.session_token, "session_token", MAX_TOKEN_LENGTH)?
            };
            Ok(EndpointConfig::Server {
                bind_address,
                certificate_path,
                private_key_path,
                session_token,
                options,
            })
        }
        2 => {
            let remote_address = unsafe {
                required_string(config.remote_address, "remote_address", MAX_ADDRESS_LENGTH)?
            }
            .parse()
            .context("remote_address is not a socket address")?;
            let server_name = unsafe {
                required_string(config.server_name, "server_name", MAX_SERVER_NAME_LENGTH)?
            };
            let certificate_sha256 =
                unsafe { required_string(config.certificate_sha256, "certificate_sha256", 64)? };
            let decoded = hex::decode(&certificate_sha256)
                .context("certificate_sha256 is not valid hexadecimal")?;
            if decoded.len() != 32 {
                bail!("certificate_sha256 must contain exactly 32 bytes");
            }
            let session_token = unsafe {
                required_string(config.session_token, "session_token", MAX_TOKEN_LENGTH)?
            };
            Ok(EndpointConfig::Client {
                remote_address,
                server_name,
                certificate_sha256,
                session_token,
                options,
            })
        }
        mode => bail!("unsupported endpoint mode {mode}"),
    }
}

type RoleConnection = (Connection, kynet::SendStream, kynet::RecvStream);

async fn hold_connections(
    shared: &Shared,
    media: RoleConnection,
    interaction: RoleConnection,
) -> Result<()> {
    shared.set_state(EndpointState::Ready);
    let media_connection = media.0.clone();
    let interaction_connection = interaction.0.clone();
    tokio::select! {
        _ = shared.stop_notify.notified() => {},
        result = media_connection.closed() => {
            result.context("media connection closed")?;
        },
        result = interaction_connection.closed() => {
            result.context("interaction connection closed")?;
        },
    }
    media.0.close(0, "StationConnect endpoint stopping");
    interaction.0.close(0, "StationConnect endpoint stopping");
    Ok(())
}

async fn run_server(
    shared: Arc<Shared>,
    bind_address: SocketAddr,
    certificate_path: &Path,
    private_key_path: &Path,
    session_token: &str,
    options: RuntimeOptions,
) -> Result<()> {
    let certificate = kynet::cert::load_cert_from_pem_file(certificate_path).await?;
    let private_key = kynet::cert::load_private_key_from_pem_file(private_key_path).await?;
    let server_options = kynet::common::CommonServerOptions {
        max_idle_timeout: Some(options.idle_timeout),
        keep_alive_interval: Some(options.keep_alive_interval),
    };
    let server = Connection::start_server_on_addr(
        bind_address,
        vec![certificate],
        private_key,
        &server_options,
    )?;
    let deadline = tokio::time::Instant::now() + options.handshake_timeout;
    let mut media = None;
    let mut interaction = None;

    while media.is_none() || interaction.is_none() {
        let candidate = tokio::select! {
            _ = shared.stop_notify.notified() => {
                server.close(0, "StationConnect endpoint stopping");
                return Ok(());
            },
            result = tokio::time::timeout_at(
                deadline,
                accept_authenticated_candidate(&server, session_token),
            ) => result.context("timed out waiting for authenticated QUIC roles")?,
        };
        let Ok((role, connection, mut send, recv)) = candidate else {
            if tokio::time::Instant::now() >= deadline {
                bail!("timed out waiting for authenticated QUIC roles");
            }
            continue;
        };
        let slot = match role {
            ConnectionRole::Media => &mut media,
            ConnectionRole::Interaction => &mut interaction,
        };
        if slot.is_some() {
            connection.close(2, "duplicate connection role");
            continue;
        }
        send.write_all(&[0]).await?;
        send.flush().await?;
        *slot = Some((connection, send, recv));
    }

    let result = hold_connections(
        &shared,
        media.expect("media role checked"),
        interaction.expect("interaction role checked"),
    )
    .await;
    server.close(0, "StationConnect endpoint stopping");
    result
}

async fn run_client(
    shared: Arc<Shared>,
    remote_address: SocketAddr,
    server_name: &str,
    certificate_sha256: &str,
    session_token: &str,
    options: RuntimeOptions,
) -> Result<()> {
    let client_options = kynet::quinn::QuinnClientOptions {
        max_idle_timeout: Some(options.idle_timeout),
        keep_alive_interval: Some(options.keep_alive_interval),
        certificate_hash: Some(certificate_sha256.to_owned()),
    };
    let connect = async {
        let media = connect_authenticated(
            remote_address,
            server_name,
            &client_options,
            session_token,
            ConnectionRole::Media,
        )
        .await?;
        let interaction = connect_authenticated(
            remote_address,
            server_name,
            &client_options,
            session_token,
            ConnectionRole::Interaction,
        )
        .await?;
        Ok::<_, anyhow::Error>((media, interaction))
    };
    let (media, interaction) = tokio::select! {
        _ = shared.stop_notify.notified() => return Ok(()),
        result = tokio::time::timeout(options.handshake_timeout, connect) => {
            result.context("timed out establishing authenticated QUIC roles")??
        },
    };
    hold_connections(&shared, media, interaction).await
}

fn endpoint_worker(config: EndpointConfig, shared: Arc<Shared>) {
    init_crypto_once();
    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .worker_threads(2)
        .thread_name("sc-datasmash")
        .build()
    {
        Ok(runtime) => runtime,
        Err(error) => {
            shared.fail(format!("failed to create transport runtime: {error}"));
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

fn catch_result(function: impl FnOnce() -> i32) -> i32 {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(function))
        .unwrap_or(SC_DATASMASH_ERROR_PANIC)
}

#[unsafe(no_mangle)]
pub extern "C" fn sc_datasmash_abi_version() -> u32 {
    ABI_VERSION
}

#[unsafe(no_mangle)]
/// Creates an endpoint and copies its configuration.
///
/// # Safety
/// `config` must point to a valid configuration whose non-null string fields
/// are NUL-terminated. `endpoint_out` must point to writable pointer storage.
pub unsafe extern "C" fn sc_datasmash_endpoint_create(
    config: *const ScDatasmashConfig,
    endpoint_out: *mut *mut ScDatasmashEndpoint,
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
        let endpoint = Box::new(ScDatasmashEndpoint {
            config,
            shared: Arc::new(Shared::new()),
            worker: Mutex::new(None),
        });
        unsafe { *endpoint_out = Box::into_raw(endpoint) };
        SC_DATASMASH_OK
    })
}

#[unsafe(no_mangle)]
/// Starts the endpoint worker exactly once.
///
/// # Safety
/// `endpoint` must be null or a live handle returned by
/// [`sc_datasmash_endpoint_create`] that has not been destroyed.
pub unsafe extern "C" fn sc_datasmash_endpoint_start(endpoint: *mut ScDatasmashEndpoint) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        let mut worker = endpoint.worker.lock().unwrap();
        if worker.is_some() || endpoint.shared.state() != EndpointState::Idle {
            return SC_DATASMASH_ERROR_INVALID_STATE;
        }
        endpoint.shared.set_state(EndpointState::Starting);
        let config = endpoint.config.clone();
        let shared = endpoint.shared.clone();
        match std::thread::Builder::new()
            .name("sc-datasmash-endpoint".to_owned())
            .spawn(move || endpoint_worker(config, shared))
        {
            Ok(handle) => {
                *worker = Some(handle);
                SC_DATASMASH_OK
            }
            Err(error) => {
                endpoint.shared.fail(error);
                SC_DATASMASH_ERROR_RUNTIME
            }
        }
    })
}

#[unsafe(no_mangle)]
/// Waits for the endpoint to become ready or enter a terminal state.
///
/// # Safety
/// `endpoint` must be null or a live handle returned by
/// [`sc_datasmash_endpoint_create`] that has not been destroyed.
pub unsafe extern "C" fn sc_datasmash_endpoint_wait_ready(
    endpoint: *mut ScDatasmashEndpoint,
    timeout_ms: u32,
) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        let timeout = Duration::from_millis(u64::from(timeout_ms));
        let status = endpoint.shared.status.lock().unwrap();
        let (status, _) = endpoint
            .shared
            .changed
            .wait_timeout_while(status, timeout, |status| {
                matches!(status.state, EndpointState::Idle | EndpointState::Starting)
            })
            .unwrap();
        match status.state {
            EndpointState::Ready => SC_DATASMASH_OK,
            EndpointState::Idle | EndpointState::Starting => SC_DATASMASH_TIMEOUT,
            EndpointState::Failed => SC_DATASMASH_ERROR_RUNTIME,
            _ => SC_DATASMASH_ERROR_INVALID_STATE,
        }
    })
}

#[unsafe(no_mangle)]
/// Returns the current endpoint state.
///
/// # Safety
/// `endpoint` must be null or a live handle returned by
/// [`sc_datasmash_endpoint_create`] that has not been destroyed.
pub unsafe extern "C" fn sc_datasmash_endpoint_state(endpoint: *const ScDatasmashEndpoint) -> u32 {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        unsafe { endpoint.as_ref() }
            .map(|endpoint| endpoint.shared.state() as u32)
            .unwrap_or(EndpointState::Invalid as u32)
    }))
    .unwrap_or(EndpointState::Invalid as u32)
}

#[unsafe(no_mangle)]
/// Stops the worker and waits for it to exit.
///
/// # Safety
/// `endpoint` must be null or a live handle returned by
/// [`sc_datasmash_endpoint_create`] that has not been destroyed.
pub unsafe extern "C" fn sc_datasmash_endpoint_stop(endpoint: *mut ScDatasmashEndpoint) -> i32 {
    catch_result(|| {
        let Some(endpoint) = (unsafe { endpoint.as_ref() }) else {
            return SC_DATASMASH_ERROR_INVALID_ARGUMENT;
        };
        let state = endpoint.shared.state();
        if state == EndpointState::Idle {
            endpoint.shared.stop.store(true, Ordering::Release);
            endpoint.shared.set_state(EndpointState::Stopped);
            return SC_DATASMASH_OK;
        }
        if matches!(state, EndpointState::Starting | EndpointState::Ready) {
            endpoint.shared.set_state(EndpointState::Stopping);
        }
        endpoint.shared.stop.store(true, Ordering::Release);
        endpoint.shared.stop_notify.notify_waiters();
        if let Some(worker) = endpoint.worker.lock().unwrap().take()
            && worker.join().is_err()
        {
            endpoint.shared.fail("transport worker panicked");
            return SC_DATASMASH_ERROR_PANIC;
        }
        if endpoint.shared.state() == EndpointState::Failed {
            SC_DATASMASH_ERROR_RUNTIME
        } else {
            endpoint.shared.set_state(EndpointState::Stopped);
            SC_DATASMASH_OK
        }
    })
}

#[unsafe(no_mangle)]
/// Stops and destroys an endpoint.
///
/// # Safety
/// `endpoint` must be null or a live handle returned by
/// [`sc_datasmash_endpoint_create`]. A non-null handle must be passed exactly
/// once and must not be used concurrently after destruction begins.
pub unsafe extern "C" fn sc_datasmash_endpoint_destroy(endpoint: *mut ScDatasmashEndpoint) {
    if endpoint.is_null() {
        return;
    }
    let _ = std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let endpoint = unsafe { Box::from_raw(endpoint) };
        endpoint.shared.stop.store(true, Ordering::Release);
        endpoint.shared.stop_notify.notify_waiters();
        if let Some(worker) = endpoint.worker.lock().unwrap().take() {
            let _ = worker.join();
        }
    }));
}

#[unsafe(no_mangle)]
/// Copies the endpoint's last error into caller-owned storage.
///
/// # Safety
/// `endpoint` must be null or a live, non-destroyed endpoint. When `buffer` is
/// non-null and `buffer_size` is nonzero, it must reference at least that many
/// writable bytes.
pub unsafe extern "C" fn sc_datasmash_endpoint_last_error(
    endpoint: *const ScDatasmashEndpoint,
    buffer: *mut c_char,
    buffer_size: usize,
) -> usize {
    std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| {
        let error = unsafe { endpoint.as_ref() }
            .map(|endpoint| endpoint.shared.status.lock().unwrap().error.clone())
            .unwrap_or_else(|| "invalid endpoint".to_owned());
        let required = error.len().saturating_add(1);
        if !buffer.is_null() && buffer_size > 0 {
            let copy_length = error.len().min(buffer_size - 1);
            unsafe {
                ptr::copy_nonoverlapping(error.as_ptr(), buffer.cast::<u8>(), copy_length);
                *buffer.add(copy_length) = 0;
            }
        }
        required
    }))
    .unwrap_or(0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CString;

    fn base_config() -> ScDatasmashConfig {
        ScDatasmashConfig {
            struct_size: std::mem::size_of::<ScDatasmashConfig>() as u32,
            abi_version: ABI_VERSION,
            mode: 0,
            handshake_timeout_ms: 0,
            idle_timeout_ms: 0,
            keep_alive_interval_ms: 0,
            bind_address: ptr::null(),
            remote_address: ptr::null(),
            server_name: ptr::null(),
            certificate_path: ptr::null(),
            private_key_path: ptr::null(),
            certificate_sha256: ptr::null(),
            session_token: ptr::null(),
        }
    }

    #[test]
    fn public_header_abi_values_are_stable() {
        assert_eq!(sc_datasmash_abi_version(), 1);
        assert_eq!(EndpointState::Idle as u32, 1);
        assert_eq!(EndpointState::Failed as u32, 6);
    }

    #[test]
    fn server_config_is_copied_and_validated() {
        let bind = CString::new("127.0.0.1:47489").unwrap();
        let cert = CString::new("/tmp/cert.pem").unwrap();
        let key = CString::new("/tmp/key.pem").unwrap();
        let token = CString::new("session-token").unwrap();
        let mut config = base_config();
        config.mode = 1;
        config.bind_address = bind.as_ptr();
        config.certificate_path = cert.as_ptr();
        config.private_key_path = key.as_ptr();
        config.session_token = token.as_ptr();

        let parsed = unsafe { parse_config(&config) }.unwrap();
        match parsed {
            EndpointConfig::Server { bind_address, .. } => {
                assert_eq!(bind_address, "127.0.0.1:47489".parse().unwrap());
            }
            EndpointConfig::Client { .. } => panic!("unexpected client config"),
        }
    }

    #[test]
    fn client_requires_an_exact_certificate_hash() {
        let remote = CString::new("127.0.0.1:47489").unwrap();
        let name = CString::new("localhost").unwrap();
        let hash = CString::new("00").unwrap();
        let token = CString::new("session-token").unwrap();
        let mut config = base_config();
        config.mode = 2;
        config.remote_address = remote.as_ptr();
        config.server_name = name.as_ptr();
        config.certificate_sha256 = hash.as_ptr();
        config.session_token = token.as_ptr();

        assert!(unsafe { parse_config(&config) }.is_err());
    }

    #[test]
    fn create_start_failure_and_destroy_are_safe() {
        let bind = CString::new("127.0.0.1:0").unwrap();
        let cert = CString::new("/definitely/missing/cert.pem").unwrap();
        let key = CString::new("/definitely/missing/key.pem").unwrap();
        let token = CString::new("session-token").unwrap();
        let mut config = base_config();
        config.mode = 1;
        config.bind_address = bind.as_ptr();
        config.certificate_path = cert.as_ptr();
        config.private_key_path = key.as_ptr();
        config.session_token = token.as_ptr();
        let mut endpoint = ptr::null_mut();

        assert_eq!(
            unsafe { sc_datasmash_endpoint_create(&config, &mut endpoint) },
            SC_DATASMASH_OK
        );
        assert!(!endpoint.is_null());
        assert_eq!(
            unsafe { sc_datasmash_endpoint_start(endpoint) },
            SC_DATASMASH_OK
        );
        assert_eq!(
            unsafe { sc_datasmash_endpoint_wait_ready(endpoint, 2_000) },
            SC_DATASMASH_ERROR_RUNTIME
        );
        assert_eq!(
            unsafe { sc_datasmash_endpoint_state(endpoint) },
            EndpointState::Failed as u32
        );
        let required = unsafe { sc_datasmash_endpoint_last_error(endpoint, ptr::null_mut(), 0) };
        assert!(required > 1);
        unsafe { sc_datasmash_endpoint_destroy(endpoint) };
    }

    #[test]
    fn stop_before_start_is_idempotent() {
        let bind = CString::new("127.0.0.1:0").unwrap();
        let cert = CString::new("/tmp/cert.pem").unwrap();
        let key = CString::new("/tmp/key.pem").unwrap();
        let token = CString::new("session-token").unwrap();
        let mut config = base_config();
        config.mode = 1;
        config.bind_address = bind.as_ptr();
        config.certificate_path = cert.as_ptr();
        config.private_key_path = key.as_ptr();
        config.session_token = token.as_ptr();
        let mut endpoint = ptr::null_mut();

        assert_eq!(
            unsafe { sc_datasmash_endpoint_create(&config, &mut endpoint) },
            SC_DATASMASH_OK
        );
        assert_eq!(
            unsafe { sc_datasmash_endpoint_stop(endpoint) },
            SC_DATASMASH_OK
        );
        assert_eq!(
            unsafe { sc_datasmash_endpoint_stop(endpoint) },
            SC_DATASMASH_OK
        );
        unsafe { sc_datasmash_endpoint_destroy(endpoint) };
    }
}
