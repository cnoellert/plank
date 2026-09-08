// Direct tests of the pinned Quinn batch API. TLS is verified against a
// temporary localhost fixture; no product listener, capture or OS input.
use std::{io::BufReader, sync::Arc, time::{Duration, Instant}};
use bytes::Bytes;
use quinn::{Endpoint, TransportConfig, rustls};

async fn pair(cert_path: &str, key_path: &str, datagrams: bool)
    -> (Endpoint, Endpoint, quinn::Connection, quinn::Connection) {
    let certs: Vec<_> = rustls_pemfile::certs(&mut BufReader::new(std::fs::File::open(cert_path).unwrap()))
        .collect::<Result<_, _>>().unwrap();
    let key = rustls_pemfile::private_key(&mut BufReader::new(std::fs::File::open(key_path).unwrap())).unwrap().unwrap();
    let mut transport = TransportConfig::default();
    transport.datagram_receive_buffer_size(datagrams.then_some(16 * 1024 * 1024));
    transport.datagram_send_buffer_size(16 * 1024 * 1024);
    let transport = Arc::new(transport);
    let mut server_config = quinn::ServerConfig::with_single_cert(certs.clone(), key).unwrap();
    server_config.transport_config(transport.clone());
    let server = Endpoint::server(server_config, "127.0.0.1:0".parse().unwrap()).unwrap();
    let mut roots = rustls::RootCertStore::empty();
    for cert in certs { roots.add(cert).unwrap(); }
    let mut client_config = quinn::ClientConfig::with_root_certificates(Arc::new(roots)).unwrap();
    let mut client_transport = TransportConfig::default();
    client_transport.datagram_receive_buffer_size(Some(16 * 1024 * 1024));
    client_transport.datagram_send_buffer_size(16 * 1024 * 1024);
    client_config.transport_config(Arc::new(client_transport));
    let mut client = Endpoint::client("127.0.0.1:0".parse().unwrap()).unwrap();
    client.set_default_client_config(client_config);
    let connect = client.connect(server.local_addr().unwrap(), "localhost").unwrap();
    let (a, b) = tokio::join!(connect, async { server.accept().await.unwrap().await });
    (client, server, a.unwrap(), b.unwrap())
}

async fn receive(conn: &quinn::Connection) -> Bytes {
    tokio::time::timeout(Duration::from_secs(5), conn.read_datagram()).await.unwrap().unwrap()
}

#[tokio::main(flavor = "multi_thread", worker_threads = 4)]
async fn main() {
    let args: Vec<_> = std::env::args().collect();
    assert_eq!(args.len(), 3);
    let (_ce, _se, client, server) = pair(&args[1], &args[2], true).await;
    for count in [0usize, 1, 15, 16, 17, 65] {
        let packets: Vec<_> = (0..count).map(|i| Bytes::from(format!("packet-{count}-{i}"))).collect();
        client.send_datagram_batch(&packets).unwrap();
        let expected: std::collections::HashSet<_> = packets.into_iter().collect();
        let mut actual = std::collections::HashSet::new();
        for _ in 0..count { actual.insert(receive(&server).await); }
        assert_eq!(actual, expected);
    }
    assert!(matches!(client.send_datagram_batch(&[
        Bytes::from_static(b"before-error"), Bytes::from(vec![0; 65536]), Bytes::from_static(b"not-sent")
    ]), Err(quinn::SendDatagramError::TooLarge)));
    assert_eq!(receive(&server).await, Bytes::from_static(b"before-error"));
    assert!(tokio::time::timeout(Duration::from_millis(50), server.read_datagram()).await.is_err());
    client.send_datagram_batch(&[Bytes::from_static(b"after-error")]).unwrap();
    assert_eq!(receive(&server).await, Bytes::from_static(b"after-error"));
    client.close(0u32.into(), b"test complete");
    assert!(matches!(client.send_datagram_batch(&[Bytes::from_static(b"closed")]),
                     Err(quinn::SendDatagramError::ConnectionLost(_))));
    let (_ce, _se, client, server) = pair(&args[1], &args[2], false).await;
    assert!(matches!(client.send_datagram_batch(&[Bytes::from_static(b"disabled")]),
                     Err(quinn::SendDatagramError::UnsupportedByPeer)));
    assert!(matches!(server.send_datagram_batch(&[Bytes::from_static(b"disabled")]),
                     Err(quinn::SendDatagramError::Disabled)));
    client.close(0u32.into(), b"test complete");
    println!("quinn_batch_edges=pass empty=1 boundaries=1 partial_error_wake=1 oversized=1 closed=1 unsupported=1");

    // Independent loopback connections; compare interactive round trips while
    // a video-like datagram producer uses the same connection concurrently.
    // This is not OS input, audio synchronization or a WAN qualification.
    for batch in [false, true, false, true] {
        let (_ce, _se, client, server) = pair(&args[1], &args[2], true).await;
        let sender = client.clone();
        let reader = server.clone();
        let drain = tokio::spawn(async move {
            for _ in 0..4096 { receive(&reader).await; }
        });
        let echo = tokio::spawn(async move {
            let (mut send, mut recv) = server.accept_bi().await.unwrap();
            let mut byte = [0u8];
            for _ in 0..64 {
                recv.read_exact(&mut byte).await.unwrap();
                send.write_all(&byte).await.unwrap();
            }
            send.finish().unwrap();
        });
        let packets: Vec<_> = (0..512).map(|_| Bytes::from(vec![0x55; 1000])).collect();
        let load = tokio::spawn(async move {
            for _ in 0..8 {
                if batch { sender.send_datagram_batch(&packets).unwrap(); }
                else { for p in &packets { sender.send_datagram(p.clone()).unwrap(); } }
                tokio::time::sleep(Duration::from_millis(1)).await;
            }
        });
        let (mut send, mut recv) = client.open_bi().await.unwrap();
        let mut times = Vec::new();
        for i in 0..64u8 {
            let start = Instant::now();
            send.write_all(&[i]).await.unwrap();
            let mut response = [0];
            tokio::time::timeout(Duration::from_secs(2), recv.read_exact(&mut response)).await.unwrap().unwrap();
            assert_eq!(response[0], i);
            times.push(start.elapsed().as_micros());
            tokio::time::sleep(Duration::from_millis(1)).await;
        }
        load.await.unwrap(); echo.await.unwrap(); drain.await.unwrap();
        times.sort_unstable();
        println!("quinn_batch_control batch={batch} requests=64 video_datagrams=4096 mean_us={} p95_us={} max_us={}",
                 times.iter().sum::<u128>() / 64, times[60], times[63]);
        client.close(0u32.into(), b"test complete");
    }
}
