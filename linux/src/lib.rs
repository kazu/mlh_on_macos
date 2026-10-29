pub mod core;
pub mod ibus;

use std::{os::unix::ffi::OsStringExt, path::PathBuf};
use zbus::address::{
    Address, Transport,
    transport::{Unix, UnixSocket},
};

pub fn ibus_address(value: &str) -> Result<Address, Box<dyn std::error::Error>> {
    let address: Address = value.parse()?;
    if let Transport::Unix(unix) = address.transport() {
        if let UnixSocket::File(path) = unix.path() {
            let path = path.to_str().ok_or("invalid IBus address")?;
            let path = PathBuf::from(std::ffi::OsString::from_vec(
                percent_encoding::percent_decode_str(path).collect(),
            ));
            let decoded = Address::new(Transport::Unix(Unix::new(UnixSocket::File(path))));
            return Ok(match address.guid() {
                Some(guid) => decoded.set_guid(guid.to_owned())?,
                None => decoded,
            });
        }
    }
    Ok(address)
}
