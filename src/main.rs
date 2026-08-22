mod api;
mod appload;
mod backend;
mod config;
mod models;
mod pairing;

use anyhow::{Context, Result};

use appload::AppLoadSocket;
use backend::Backend;
use config::Config;

fn main() -> Result<()> {
    let socket_path = std::env::args()
        .nth(1)
        .context("expected the AppLoad socket path as argv[1]")?;

    let config = Config::load()?;
    let socket = AppLoadSocket::connect(&socket_path)?;
    let result = Backend::new(config).run(socket);
    if let Err(err) = &result {
        eprintln!("saver-remarkable: {err:#}");
    }
    result
}
