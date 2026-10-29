use std::io::{Read, Write};
use std::net::TcpListener;
use std::time::Duration;

fn main() {
    let listener = TcpListener::bind("127.0.0.1:0").unwrap();
    println!("{}", listener.local_addr().unwrap().port());
    std::io::stdout().flush().unwrap();
    for request_number in 0..4 {
        let (mut stream, _) = listener.accept().unwrap();
        stream
            .set_read_timeout(Some(Duration::from_secs(5)))
            .unwrap();
        let mut request = Vec::new();
        let mut chunk = [0_u8; 4096];
        loop {
            let n = stream.read(&mut chunk).unwrap();
            assert_ne!(n, 0);
            request.extend_from_slice(&chunk[..n]);
            if let Some(end) = request.windows(4).position(|w| w == b"\r\n\r\n") {
                let headers = String::from_utf8_lossy(&request[..end]);
                let length = headers
                    .lines()
                    .find_map(|line| {
                        let (name, value) = line.split_once(':')?;
                        name.eq_ignore_ascii_case("content-length")
                            .then(|| value.trim().parse::<usize>().unwrap())
                    })
                    .unwrap();
                if request.len() >= end + 4 + length {
                    break;
                }
            }
        }
        assert!(String::from_utf8_lossy(&request).contains("hello"));
        stream
            .write_all(
                b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n",
            )
            .unwrap();
        stream
            .write_all(b"data: {\"choices\":[{\"delta\":{\"content\":\"AB\"}}]}\n\n")
            .unwrap();
        stream.flush().unwrap();
        std::thread::sleep(Duration::from_millis(if request_number == 2 {
            2000
        } else {
            150
        }));
        let result = stream.write_all(
            b"data: {\"choices\":[{\"delta\":{\"content\":\"C\"}}]}\n\ndata: [DONE]\n\n",
        );
        if request_number != 2 {
            result.unwrap();
        }
    }
}
