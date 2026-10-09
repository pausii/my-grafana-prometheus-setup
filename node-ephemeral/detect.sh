# ============================================================
# detect.sh — work out this host's identity
# Sourced by bootstrap.sh. Not run on its own.
# ============================================================
# The detection chain, from most trustworthy to roughest:
#
#   1. DMI  /sys/class/dmi/id/sys_vendor
#      Written into the virtual firmware by the hypervisor. The
#      most reliable signal for cloud VMs. But on a DEDICATED
#      server it holds the real motherboard vendor (e.g.
#      "Micro-Star"), not the provider.
#   2. Reverse DNS of the public address
#      Often carries the zone code, e.g. us-sjo1.upcloud.host.
#   3. Metadata at 169.254.169.254
#      A link-local address meaningful only inside a VM. The
#      format differs per provider.
#   4. Geo-IP
#      The last resort. Gives country, city and the ASN owner.
#
# Whatever it concludes can be overridden with --server,
# --country, --city and --provider.

slug() { printf '%s' "$1" | tr 'A-Z' 'a-z' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//'; }

# Sets two globals: PUBLIC_IP and IP_FAMILY.
#
# Deliberately NOT written as "echo" plus $(...) — command
# substitution runs in a subshell, so an IP_FAMILY assigned inside
# would never be visible to the caller.
detect_public_ip() {
  local u
  PUBLIC_IP=""; IP_FAMILY=""

  # IPv4 first. Practical reasons: the address is far shorter as a
  # server name, and in most places it is the path you actually
  # SSH over when something needs looking at.
  for u in "https://ifconfig.me" "https://api.ipify.org"; do
    PUBLIC_IP=$(curl -4 -fsS --max-time 6 "$u" 2>/dev/null || true)
    [[ -n "$PUBLIC_IP" ]] && { IP_FAMILY="-4"; return; }
  done

  # IPv6 only if there genuinely is no public IPv4.
  for u in "https://ifconfig.me" "https://api6.ipify.org"; do
    PUBLIC_IP=$(curl -6 -fsS --max-time 6 "$u" 2>/dev/null || true)
    [[ -n "$PUBLIC_IP" ]] && { IP_FAMILY="-6"; return; }
  done
}

detect_rdns() {
  [[ -n "${1:-}" ]] || return 0
  getent hosts "$1" 2>/dev/null | awk '{print $2}' | head -1 || true
}

detect_provider() {
  local v="" r="${RDNS:-}"
  v=$(tr 'A-Z' 'a-z' < /sys/class/dmi/id/sys_vendor 2>/dev/null || true)

  case "$v" in
    *upcloud*)          echo upcloud;      return;;
    *hetzner*)          echo hetzner;      return;;
    *digitalocean*)     echo digitalocean; return;;
    *amazon*|*ec2*)     echo aws;          return;;
    *google*)           echo gcp;          return;;
    *microsoft*)        echo azure;        return;;
    *vultr*)            echo vultr;        return;;
    *scaleway*)         echo scaleway;     return;;
    *linode*|*akamai*)  echo linode;       return;;
    *oracle*)           echo oracle;       return;;
  esac

  case "$r" in
    *.upcloud.host)         echo upcloud;      return;;
    *.ovh.net|*.ovh.ca)     echo ovh;          return;;
    *hetzner*|*.your-server.de) echo hetzner;  return;;
    *digitalocean*)         echo digitalocean; return;;
    *vultr*)                echo vultr;        return;;
    *linode*|*.members.linode.com) echo linode; return;;
    *contabo*)              echo contabo;      return;;
  esac

  # OpenStack with no other clue: the provider is unknown, but at
  # least we know it is an OpenStack VM.
  [[ "$v" == *openstack* ]] && { echo openstack; return; }
  echo unknown
}

# Returns a zone code such as "us-sjo1" when one can be found.
detect_zone() {
  local z=""
  case "${PROVIDER}" in
    upcloud)
      # 203-0-113-10.us-sjo1.upcloud.host
      z=$(printf '%s' "${RDNS:-}" | awk -F. '{print $2}' \
          | grep -E '^[a-z]{2}-[a-z]{3}[0-9]*$' || true)
      # fallback: hostname like ubuntu-2cpu-4gb-us-sjo1
      [[ -z "$z" ]] && z=$(hostname | grep -oE '[a-z]{2}-[a-z]{3}[0-9]*$' || true)
      ;;
    ovh|openstack)
      z=$(curl -fsS --max-time 4 \
            http://169.254.169.254/openstack/latest/meta_data.json 2>/dev/null \
          | grep -o '"availability_zone"[^,]*' | cut -d'"' -f4 || true)
      ;;
    hetzner)
      z=$(curl -fsS --max-time 4 \
            http://169.254.169.254/hetzner/v1/metadata 2>/dev/null \
          | grep -E '^[[:space:]]*(availability-zone|region):' \
          | awk '{print $2}' | head -1 || true)
      ;;
    aws)
      z=$(curl -fsS --max-time 4 \
            http://169.254.169.254/latest/meta-data/placement/availability-zone 2>/dev/null || true)
      ;;
  esac
  printf '%s' "$z"
}

detect_geo() {
  local u j cc
  local -a votes=()
  GEO_CC="" GEO_CITY="" GEO_ASN_ORG=""

  # Country is decided by MAJORITY VOTE across several services,
  # not by the first one that answers. This is not paranoia — a
  # real case: for one hosting provider's IPv4 address, ifconfig.co
  # answered GB while ipinfo.io and ip-api.com both answered FR.
  # FR was correct; ifconfig.co reports the country the IP block is
  # REGISTERED in, not where the machine physically sits. Hosting
  # providers routinely register blocks in a different country from
  # the datacenter using them.
  #
  # City and ASN are taken from the first source that has them —
  # they rarely disagree as sharply as country.
  #
  # ifconfig.co stays in the list because it is the only one of
  # these four that serves IPv6. Without it, IPv6-only hosts fail
  # outright.
  for u in "https://ifconfig.co/json" "https://ipinfo.io/json" \
           "http://ip-api.com/json/" "https://ipapi.co/json/"; do
    [[ -n "$GEO_CC" && -n "$GEO_CITY" && -n "$GEO_ASN_ORG" ]] && break
    # Follow the same address family as the server name, so the
    # city and ASN belong to the address actually being used.
    j=$(curl ${IP_FAMILY:-} -fsS --max-time 8 "$u" 2>/dev/null || true)
    [[ -n "$j" ]] || continue

    # country_iso / country_code / countryCode are already
    # two-letter codes. A plain "country" field holds the long name
    # ("Finland"), so it only counts if it happens to be two
    # characters.
    cc=$(printf '%s' "$j" \
      | grep -oE '"(country_iso|country_code|countryCode|country)":[[:space:]]*"[A-Za-z]{2}"' \
      | cut -d'"' -f4 | head -1 | tr 'A-Z' 'a-z')
    [[ -n "$cc" ]] && votes+=("$cc")

    [[ -z "$GEO_CITY" ]] && GEO_CITY=$(printf '%s' "$j" \
      | grep -oE '"city":[[:space:]]*"[^"]+"' | cut -d'"' -f4 | head -1)

    # The ASN owner's name. This is what rescues DEDICATED servers,
    # whose firmware reports the motherboard vendor rather than the
    # provider.
    [[ -z "$GEO_ASN_ORG" ]] && GEO_ASN_ORG=$(printf '%s' "$j" \
      | grep -oE '"(asn_org|org|isp)":[[:space:]]*"[^"]+"' | cut -d'"' -f4 | head -1)
  done

  if (( ${#votes[@]} > 0 )); then
    GEO_CC=$(printf '%s\n' "${votes[@]}" | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')
    GEO_VOTES=$(printf '%s ' "${votes[@]}")
  fi
  [[ -n "$GEO_CC" ]]
}

# Last layer of provider detection: the ASN owner's name. Used only
# when DMI and reverse DNS give nothing at all.
provider_from_asn() {
  local o; o=$(printf '%s' "${1:-}" | tr 'A-Z' 'a-z')
  case "$o" in
    *hetzner*)                echo hetzner ;;
    *ovh*)                    echo ovh ;;
    *upcloud*)                echo upcloud ;;
    *digitalocean*)           echo digitalocean ;;
    *amazon*|*aws*)           echo aws ;;
    *google*)                 echo gcp ;;
    *microsoft*)              echo azure ;;
    *vultr*|*choopa*)         echo vultr ;;
    *linode*|*akamai*)        echo linode ;;
    *scaleway*|"online s.a.s"*) echo scaleway ;;
    *contabo*)                echo contabo ;;
    *oracle*)                 echo oracle ;;
    *leaseweb*)               echo leaseweb ;;
    *hostinger*)              echo hostinger ;;
    *)                        echo unknown ;;
  esac
}
