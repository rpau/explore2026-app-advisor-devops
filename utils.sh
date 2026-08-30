#!/usr/bin/env bash
# Utility functions for use in CI workflows. Source this file to use them:
#   source utils.sh

# Strips carriage returns and in-place progress lines from advisor CLI output.
cleanOutput() { tr '\r' '\n' | { grep -Ev "[🏃🔨].*\[[0-9]+m [0-9]+s\]$" || true; } }

# Downloads and installs the advisor CLI. Requires BC_REG_TOKEN and ADVISOR_VERSION env vars.
installAdvisor() {
  echo "Installing advisor CLI - version ${ADVISOR_VERSION}"
  curl -fsSL \
    -H "Authorization: Bearer ${BC_REG_TOKEN}" \
    -o /tmp/advisor-cli.tar \
    "https://packages.broadcom.com/artifactory/spring-enterprise/com/vmware/tanzu/spring/application-advisor-cli-linux/${ADVISOR_VERSION}/application-advisor-cli-linux-${ADVISOR_VERSION}.tar"
  tar -xf /tmp/advisor-cli.tar -C /tmp --strip-components=1 --exclude=./META-INF
  install /tmp/advisor /usr/local/bin/advisor
}

# Downloads and installs the trivy CLI.
installTrivy() {
  echo "Installing trivy CLI - latest version"
  curl -fsSL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh \
    | sh -s -- -b /usr/local/bin # Consider pinning a specific version.
}

# Normalize Java version properties in a pom.xml so advisor can reliably detect the JDK version:
# - if java.version is present, ensures maven.compiler.target is also set to the same value
# - removes maven.compiler.release (conflicts with the above)
# - dedupes java.version if it appears more than once (keeps the first)
# Usage: fixPomJavaProperties [-v|--verbose] [pom-file]  (default pom-file: pom.xml)
fixPomJavaProperties() {
  local verbose=false
  local pom="pom.xml"

  while [ $# -gt 0 ]; do
    case "$1" in
      -v|--verbose) verbose=true ;;
      *) pom="$1" ;;
    esac
    shift
  done

  if [ ! -f "$pom" ]; then
    echo "ERROR: $pom not found" >&2
    return 1
  fi

  local before=""
  [ "$verbose" = true ] && before=$(cat "$pom")

  perl -0777 -pi -e '
    s{[ \t]*<maven\.compiler\.release>.*?</maven\.compiler\.release>\n}{}g;

    my $count = 0;
    s{([ \t]*<java\.version>.*?</java\.version>\n)}{ $count++; $count > 1 ? "" : $1 }ge;

    if (/[ \t]*<java\.version>(\d+)<\/java\.version>\n/ && !/<maven\.compiler\.target>/) {
      my $ver = $1;
      s{([ \t]*)(<java\.version>\Q$ver\E</java\.version>\n)}{$1$2$1<maven.compiler.target>$ver</maven.compiler.target>\n};
    }
  ' "$pom"

  if [ "$verbose" = true ]; then
    echo "=== fixPomJavaProperties: $pom ==="
    local d
    d=$(diff -u <(echo "$before") "$pom" --label before --label after)
    [ -z "$d" ] && echo "(no changes)" || echo "$d"
  fi
}