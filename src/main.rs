use http_body_util::{BodyExt, Empty};
use hyper::Request;
use hyper::body::Bytes;
use hyper_rustls::HttpsConnectorBuilder;
use hyper_util::client::legacy::Client;
use hyper_util::rt::TokioExecutor;

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let connector = HttpsConnectorBuilder::new()
        .with_webpki_roots()
        .https_only()
        .enable_http1()
        .build();

    let client: Client<_, Empty<Bytes>> =
        Client::builder(TokioExecutor::new()).build(connector);

    let req = Request::builder()
        .uri("https://am.i.mullvad.net/json")
        .header("user-agent", "showcase-aws-lc-binary-size/0.1")
        .body(Empty::<Bytes>::new())?;

    let res = client.request(req).await?;
    let body = res.into_body().collect().await?.to_bytes();
    print!("{}", std::str::from_utf8(&body)?);
    Ok(())
}
