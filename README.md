## Description
Generates an X.509 certificate signed with a CA’s private key.

## Usage
```bash
generate-user-certificate -c <ca_certificate> -k <ca_private_key> -l years -z <output_zip_file>
                          [-n commonName] [-g givenName] [-s surname] [-C country] [-o organization]
                          [-a subjectAlternativeName]

generate-user-certificate -h

Options:
   -h     Print this help and exit
   -c     Path to CA certificate
   -k     Path to CA certificate private key
   -z     Path to the output .zip file

Certificate parameters:
   -l     Certificate lifetime in years. The end date cannot be later than the CA certificate expiration date
   -n     Common Name (CN). If not provided, will be composed from Given Name (GN) and Surname (SN)
   -g     Given Name (GN)
   -s     Surname (SN)
   -C     Country Name (C)
   -o     Organization Name (O)
   -a     Subject alternative name. If not provided, will be set to Common Name (CN)
```

## Pre-run configuration

The user who runs the script must have read-write permissions to the following `/etc/swanctl/` folders:

- bliss
- ecdsa
- pkcs12
- pkcs8
- private
- pubkey
- rsa
- x509
- x509aa
- x509ac
- x509ca
- x509crl
- x509ocsp

It may be convenient to have a group and assign the appropriate ACL rules (requires the filesystem to support this) to avoid running the script as root.

For group `cert-manager`, this could be done like this:
```bash
for dir in bliss ecdsa pkcs12 pkcs8 private pubkey rsa x509 x509aa x509ac x509ca x509crl x509ocsp
do
    sudo setfacl -m g:cert-manager:rwx /etc/swanctl/$dir;
    sudo setfacl -dm g:cert-manager:rw /etc/swanctl/$dir;
done
```