#!/bin/bash -e

declare -r swanPath="/etc/swanctl"
declare -r keyPath="${swanPath}/pkcs8"
declare -r pkcs12Path="${swanPath}/pkcs12"
declare -r certPath="${swanPath}/x509"

declare -r privateKeyExtension="pem"
declare -r certificateRequestExtension="pem"
declare -r certificateExtension="pem"
declare -r pkcs12Extension="p12"

declare -Ar rdnTypes=(
    [commonName]="CN"
    [surname]="SN"
    [countryName]="C"
    [organizationName]="O"
    [givenName]="GN"
)

function log() {
    local message="${1}"
    shift 1
    printf "%s   $message\n" "$(date --iso-8601=ns)" "$@"
}

function help()
{
   echo "Generates an X.509 certificate signed with a CA's private key. Puts all generated files to a .zip archive."
   echo "generate-user-certificate -c <ca_certificate> -k <ca_private_key> -l years -z <output_zip_file>"
   echo "                          [-n commonName] [-g givenName] [-s surname] [-C country] [-o organization]"
   echo "                          [-a subjectAlternativeName]"
   echo "   -h     Print this help and exit"
   echo "   -c     Path to CA certificate"
   echo "   -k     Path to CA certificate private key"
   echo "   -z     Path to the output .zip file"
   echo "certificate parameters:"
   echo "   -l     Certificate lifetime in years. The end date cannot be later than the CA certificate expiration date"
   echo "   -n     Common Name (CN). If not provided, composed from Given Name (GN) and Surname (SN). Exits if no GN and SN is specified"
   echo "   -g     Given Name (GN)"
   echo "   -s     Surname (SN)"
   echo "   -C     Country Name (C)"
   echo "   -o     Organization Name (O)"
   echo "   -a     Subject alternative name. Default: Common Name (CN)"
   echo
}

function exit_wrong_usage()
{
   local message=${1}
   if [ ${message:+x} ]
   then
      log "Wrong usage: %s" "$message"
   fi
   help
   exit 1
}

function joinBy {
    local d=${1-} f=${2-}
    if shift 2
    then
        printf %s "$f" "${@/#/$d}"
    fi
}

function prependAndJoin() {
    local prefix="${1-}"
    if shift 1
    then
        echo "${@/#/$prefix}"
    fi
}

function changeOwner() {
    local path="${1}"
    local newOwner="${2:-root}"
    local newGroup="${3:-root}"
    chown "$newOwner":"$newGroup" "$path"
    log "Changed %s ownership to %s:%s" "$path" "$newOwner" "$newGroup"
}

function makeReadable() {
    local path="${1}"
    chmod 644 "$path"
    log "Changed %s access attributes to '-rw-r--r--'" "$path"
}

function fixPermissions() {
    local path="${1}"
    makeReadable "$path"
}

function toEpoch() {
    local -r value="${1}"
    local -ir epoch=$(date -d "${1}" +%s)
    echo $epoch
}

function addYears() {
    declare -i years=${1}
    echo "$(date -d "$years years")"
}

function getDaysBetweenNowPlusYears() {
    declare -i years=${1}
    local futureDate="$(addYears $years)"
    echo $[(`toEpoch "$futureDate"` - `toEpoch "$(date)"` + 1) + 86400/ 86400]
}

function getCertificatecommonName() {
    local certificate="${1}"
    echo "$(openssl x509 -in "$certificate" -noout -subject -nameopt multiline | sed -n 's/ *commonName *= //p')"
}

function getCertificateExpireDate() {
    local certificate="${1}"
    notAfter="$(openssl x509 -in "$certificate" -noout -enddate | cut -d '=' -f 2)"
    echo "$(date -d "$notAfter")"
}

function generatePrivateKey() {
    local output="${1}"
    pki --gen --type ed25519 --outform pem > "$output"
}

function generateCsr() {
    local output="${1}"
    local privateKey="${2}"
    local distinguishedName="${3}"
    local alternativeName="${4}"

    if [ ! -z "${alternativeName// }" ]
    then
        log "Subject alternative name: %s" "$alternativeName"
    fi

    pki --req --type priv --in "$privateKey" \
        --dn "$distinguishedName" \
        $(prependAndJoin '--san ' "$alternativeName") \
        --outform pem > "$output"
}

function generateCertificate() {
    local output="${1}"
    local request="${2}"
    local lifetime="${3}"

    if shift 3
    then
        local flags=()
        for flag in "$@"
        do
            if [ ! -z "${flag// }" ]
            then
                flags+=($flag)
            fi
        done
    fi

    log "Flags to generate a certificate: %s" "$(joinBy ', ' ${flags[@]@Q})"
    pki --issue --type pkcs10 \
        --cacert "$caCert" --cakey "$caKey" \
        --in "$request" \
        --lifetime $lifetime \
        $(prependAndJoin '--flag ' ${flags[@]@Q}) \
        --outform pem > "$output"
}

function printCertificateData() {
    local file="${1}"
    pki --print --in "$file"
    echo
}

function generatePkcs12() {
    local output="${1}"
    local privateKey="${2}"
    local certificate="${3}"
    local containerName="${4}"

    openssl pkcs12 -export \
        -inkey "$privateKey" \
        -in "$certificate" \
        -name "$containerName" \
        -certfile "$caCert" \
        -caname "$(getCertificatecommonName "$caCert")" \
        -out "$output"
}

function packToZip() {
    local output="${1}"
    local privateKey="${2}"
    local certificate="${3}"
    local pkcs12="${4}"

    tmpFolder="$(mktemp -d)"
    log "Temp folder %s created" "$tmpFolder"

    declare -r packedPrivateKeyName="key.$privateKeyExtension"
    declare -r packedCertificateName="certificate.$certificateExtension"
    declare -r packedPkcs12Name="certificate.$pkcs12Extension"

    cp "$privateKey" "$tmpFolder/$packedPrivateKeyName"
    cp "$cert" "$tmpFolder/$packedCertificateName"
    cp "$pkcs12" "$tmpFolder/$packedPkcs12Name"

    zip -jrmq "$output" "${tmpFolder}"
    log "Generated files were put in %s" "$output"

    rmdir "$tmpFolder"
}

declare -A data
while [ $OPTIND -le "$#" ]
do
   if getopts ":hc:k:l:z:n:g:s:C:o:a:" option
   then
      case $option in
         h) help; exit;;
         c) declare -r caCert="$OPTARG";;
         k) declare -r caKey="$OPTARG";;
         l) declare -r certificateLifetimeYears="$OPTARG";;
         z) declare -r outputFile="$OPTARG";;
         n) data[commonName]="$OPTARG";;
         g) data[givenName]="$OPTARG";;
         s) data[surname]="$OPTARG";;
         C) data[countryName]="$OPTARG";;
         o) data[organizationName]="$OPTARG";;
         a) alternativeName="$OPTARG";;
         *) exit_wrong_usage "invalid option '$OPTARG'";;
      esac
  fi
done

if [ -z "${outputFile// }" ]
then
    log "Output filename cannot be empty."
    exit 1
else
    outputFolder="$(dirname "$outputFile")"
    if [ ! -w "$outputFolder" ]
    then
        log "%s is not writeable." "$outputFolder"
        exit 1
    fi
fi

if [ -z "${data[commonName]// }" ]
then
    givenName=${data[givenName]}
    surname=${data[surname]}
    if [[ ( -z "${givenName// }" ) && ( -z "${surname// }" ) ]]
    then
        log "[ERR] Common name not given but neither first name or surname is provided."
        exit 1
    else
        log "Common name not given and will be constructed from the first and last name"
        fullName=("$givenName" "$surname")
        data[commonName]="$(joinBy ' ' ${fullName[@]})"
    fi
fi

if ! [[ $certificateLifetimeYears =~ ^[0-9]+$ ]]
then
    log "[ERR] Incorrect certificate lifetime value: $certificateLifetimeYears."
    exit 1
elif [ $certificateLifetimeYears -eq 0 ]
then
    log "[ERR] Certificate lifetime cannot be 0."
    exit 1
else
    caCertificateExpirationDate="$(getCertificateExpireDate "$caCert")"
    caCertificateExpirationEpoch=$(toEpoch "$caCertificateExpirationDate")
    log "CA certificate expiration date: %s -> %d" "$caCertificateExpirationDate" $caCertificateExpirationEpoch

    supposedExpirationDate="$(addYears $certificateLifetimeYears)"
    supposedExpirationEpoch=$(toEpoch "$supposedExpirationDate")
    log "New certificate supposed expiration date: %s -> %d" "$supposedExpirationDate" $supposedExpirationEpoch

    if [ $supposedExpirationEpoch -ge $caCertificateExpirationEpoch ]
    then
        log "[ERR] CA certificate expires earlier than in %d year(s): %s >= %s" $certificateLifetimeYears "$supposedExpirationDate" "$caCertificateExpirationDate"
    fi
fi

commonName="${data[commonName]}"

if [ -z "${alternativeName// }" ]
then
    log "Alternative name not provided and will be set to Common Name = %s" "$commonName"
    alternativeName="$commonName"
fi

# Translate to lower case & collapse all consecutive whitespaces to a single dot
normalizedCommonName=$(echo "${commonName,,}" | sed -E 's/[[:space:]]+/./g')
log "Normalized: '%s' -> '%s'" "$commonName" "$normalizedCommonName"


privateKey="$keyPath/$normalizedCommonName.$privateKeyExtension"
generatePrivateKey "$privateKey"
log "Generated a new private key %s" "$privateKey"


log "Parameters to generate a certificate request:"
declare -A rdnValues
for key in "${!data[@]}"
do
    rdnType="${rdnTypes[$key]}"
    value="${data[$key]}"
    if [[ ( ! -z "$rdnType" ) && ( ! -z "${value// }" ) ]]
    then
        rdnValues[$key]="$rdnType=$value"
        log "\t[%s] -> [%s]" "$key" "${rdnValues[$key]}"
    fi
done

log "Generating a CSR using private key %s" "$privateKey"
csr="$(mktemp)"
dn="$(joinBy ', ' ${rdnValues[@]})"
generateCsr "$csr" "$privateKey" "$dn" "$alternativeName"
log "Generated a CSR:\n\tsubject='%s'\n\tsubject alternative name='%s'" "$dn" "$alternativeName"


declare -ri certificateLifetimeDays="$(getDaysBetweenNowPlusYears $certificateLifetimeYears)"
log "Converted certificate lifetime: %d years -> %d days" $certificateLifetimeYears $certificateLifetimeDays

log "Generating a certificate using CSR %s" "$csr"
cert="$certPath/$normalizedCommonName.$certificateExtension"
certificateFlags=(serverAuth ikeIntermediate)

generateCertificate "$cert" "$csr" $certificateLifetimeDays "${certificateFlags[@]}"
fixPermissions "$cert"

log "Certificate data:"
printCertificateData "${cert}"


rm "$csr"
log "CSR %s removed" "$csr"

log "Collecting previously generated files in a PKCS12 package"
pkcs12="$pkcs12Path/$normalizedCommonName.$pkcs12Extension"
generatePkcs12 "$pkcs12" "$privateKey" "$cert" "$commonName"
fixPermissions "$pkcs12"
log "Container %s created" "$pkcs12"

packToZip "$outputFile" "$privateKey" "$cert" "$pkcs12"
