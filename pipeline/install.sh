#!/bin/sh

VERSION="5.6.4"
LOGFILE="/tmp/install.log"
UNATTENDED="$1"
#UNATTENDED=""

# append text to logfile
logmsg() {
    if [ ! -f "$LOGFILE" ]; then
        touch "$LOGFILE"
    fi
    if [ -f "$LOGFILE" ]; then
            echo "$@" >> $LOGFILE
    fi
    echo "$@"
    return 0;
}

logmsgNoPrint() {
    if [ ! -f "$LOGFILE" ]; then
        touch "$LOGFILE"
    fi
    if [ -f "$LOGFILE" ]; then
            echo "$@" >> $LOGFILE
    fi
    return 0;
}

input_yn() {
    MSG="$1"
    while true; do
        read -p "$MSG" yn
        case $yn in
            [Yy]* ) logmsg "$MSG y"; return 0; break;;
            [Nn]* ) logmsg "$MSG n"; return 1;;
            * ) echo "Please answer y or n.";;
        esac
    done
}


# print prompt, print static blurb, read response string and
# export it as RESPONSE
# in unattended mode the response is ''
input_text() {
    local MSG TAG
    MSG="$1"
    TAG="${2:-}"

    if [ -z "${TAG}" ]; then
        logmsg "input_text: MSG=${MSG}: TAG='': No preseed question. Continuing..." 1;
    fi;

    RESPONSE=''
    echo -n "$MSG"
    if [ -n "$UNATTENDED" ]; then
        logmsg "Automatic blank input for '$MSG' in unattended mode"
        echo "(auto-default empty response)"
    else
        read RESPONSE
        logmsg "User input for '$MSG': '$RESPONSE'"
    fi
    export RESPONSE
}

printBanner() {
    echo
    echo
    echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo "$@"
    echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo

    if [ -f "$LOGFILE" ]; then
            echo '###+++' >> $LOGFILE
            echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++" >> $LOGFILE
            echo "$@" >> $LOGFILE
            echo "++++++++++++++++++++++++++++++++++++++++++++++++++++++" >> $LOGFILE
            echo '###+++' >> $LOGFILE
    fi
    return 0;
}

# run cmd, capture output and stderr and append to logfile
execPrint()
{
    logmsg ""
    logmsg "###+++"
    RES=0
    OUTPUT=$(eval "$@" 2>&1)||RES=$?
    # pre-initialised RES=0 before loop so we don't need a default value here
    if [ "${RES}" = 0 ]; then
        logmsg "EXEC: $*" "${RES}" "${OUTPUT}";
        break
    else
        logmsg "EXEC: $*" "${RES}" "${OUTPUT}";
        logmsg "execPrint '$*' failed."
    fi
    logmsg ""
    return $RES
}

# run cmd, capture output and stderr and append to logfile
execNoPrint()
{
    logmsgNoPrint ""
    RES=0
    OUTPUT=$(eval "$@" 2>&1)||RES=$?
    # pre-initialised RES=0 before loop so we don't need a default value here
    if [ "${RES}" = 0 ]; then
        logmsgNoPrint "EXEC: $*" "${RES}" "${OUTPUT}";
        break
    else
        logmsgNoPrint "EXEC: $*" "${RES}" "${OUTPUT}";
        logmsg "execNoPrint '$*' failed."
    fi
    logmsgNoPrint ""
    return $RES
}

check_missing_packages() {
    local PKG
    MISSING=''
    for PKG in "$@"; do
        if [ "$OSFLAVOUR" = "redhat" ]; then
            if [ -z $(rpm -qa "$PKG") ]; then
                MISSING="$MISSING $PKG";
                logmsg "Package $PKG is NOT installed."
            else
                logmsg "Package $PKG is installed.";
            fi
        elif [ "$OSFLAVOUR" = "debian" ] || [ "$OSFLAVOUR" = "ubuntu" ]; then
            if ! $(dpkg -l "$PKG" 2>/dev/null | grep -qE "^[hi]i"); then
                MISSING="$MISSING $PKG"
                logmsg "Package $PKG is NOT installed."
            else
                logmsg "Package $PKG is installed."
            fi
        fi
    done
    [ -z "$MISSING" ] && return 0
    return 1
}

printBanner "Open-AudIT v$VERSION installation script"
root_password=""

status="install"
if [ -f /usr/local/open-audit/LICENSE ]; then
    # This file exists in <5 and 5 >=
    # The file will not exist if the installer bails before the file copy but after directory creation
    status="upgrade"
else
    if [ ! -d /usr/local/open-audit ]; then
        # Make our install dir
        mkdir /usr/local/open-audit
    fi
fi

logmsg "Install status: $status"

# guesses os and sets $OSFLAVOUR to debian, ubuntu, redhat or '',
# also sets OS_VERSION, OS_MAJOR, OS_MINOR (and OS_PATCH if it exists),
# plus OS_ISCENTOS if flavour is redhat.
printBanner "OS Detection"
if [ -f "/etc/redhat-release" ]; then
        OSFLAVOUR=redhat
        logmsg "Detected OS flavour RedHat/CentOS/Rocky/Alma"
        # centos7: ugly triplet and gunk, eg. "CentOS Linux release 7.2.1511 (Core)"
        OS_VERSION=$(sed -re 's/(^|.* )([0-9]+\.[0-9]+(\.[0-9]+)?).*$/\2/' < /etc/redhat-release)
        OS_ISCENTOS=0;
        if grep -qF CentOS /etc/redhat-release; then
            logmsg "detected CentOS derivative of RHEL: OS_VERSION='${OS_VERSION}'"
            OS_ISCENTOS=1;
        elif grep -qF Rocky /etc/redhat-release; then
            logmsg "detected Rocky OS derivative of RHEL: OS_VERSION='${OS_VERSION}'"
            OS_ISCENTOS=1;
        elif grep -qF Alma /etc/redhat-release; then
            logmsg "detected Alma OS derivative of RHEL: OS_VERSION='${OS_VERSION}'"
            OS_ISCENTOS=1;
        elif grep -qF Fedora /etc/redhat-release; then
            OS_ISCENTOS=1;
            OS_VERSION=`sed -re 's/(^|.* )([0-9]+).*$/\2/' < /etc/redhat-release`;
            if [ "${OS_VERSION}" -ge 28 ]; then
                OS_VERSION='8.0.0';
            elif [ "${OS_VERSION}" -ge 19 ]; then
                OS_VERSION='7.0.0';
            elif [ "${OS_VERSION}" -ge 12 ]; then
                OS_VERSION='6.0.0';
            fi;
            logmsg "Detected derivative of RHEL: OS_VERSION='${OS_VERSION}'"
        fi;

        # ensure OS_ISCENTOS is defined:
        OS_ISCENTOS="${OS_ISCENTOS:-0}";

elif grep -q ID=debian /etc/os-release ; then
    OSFLAVOUR=debian
    logmsg "detected OS flavour Debian"
    OS_VERSION=$(cat /etc/debian_version)
elif grep -q ID=ubuntu /etc/os-release ; then
    OSFLAVOUR=ubuntu
    logmsg "Detected OS flavour Ubuntu"
    OS_VERSION=$(grep VERSION_ID /etc/os-release | sed -re 's/^VERSION_ID="([0-9]+\.[0-9]+(\.[0-9]+)?)"$/\1/')
fi

OS_VERSION="${OS_VERSION:-}";
OS_MAJOR=$(echo "$OS_VERSION" | cut -s -f 1 -d .)
OS_MAJOR="${OS_MAJOR:-0}";
OS_MINOR=$(echo "$OS_VERSION" | cut -s -f 2 -d .)
OS_MINOR="${OS_MINOR:-0}";
OS_PATCH=$(echo "$OS_VERSION" | cut -s -f 3 -d .)
OS_PATCH="${OS_PATCH:-0}";

logmsg "OSFLAVOUR=${OSFLAVOUR}"
logmsg "OS_VERSION=${OS_VERSION}"
logmsg "OS_MAJOR=${OS_MAJOR}"
logmsg "OS_MINOR=${OS_MINOR}"
logmsg "OS_PATCH=${OS_PATCH}"

if [ "$OSFLAVOUR" = "redhat" ]; then
    printBanner "Package Cache"
    logmsg "Please ensure your existing operating system is patched and up to date."
    logmsg "You must have run 'yum update' and been successful in order to install Open-AudIT."
    if [ -n "$UNATTENDED" ] || input_yn "Have you successfully run yum update (y/n)? "; then
        logmsg "Continuing install."
    else
        logmsg "Please re-run this installer once yum update has successfully completed."
        exit 1;
    fi
fi


if [ "$OSFLAVOUR" = "redhat" ]; then
    if [ "$OS_MAJOR" -lt 8 ] ; then
        printBanner "Supported OS Warning"
        logmsg "The minimum supported version of Redhat (and related distro's) for Open-AudIT is 8, please upgrade your OS before attempting to install Open-AudIT."
        logmsg "The installer detected $OSFLAVOUR version $OS_MAJOR."
        if [ -n "$UNATTENDED" ]; then
            exit 1;
        fi
        if ! input_yn "Should I install anyway (y/n)? "; then
            execNoPrint "mv $LOGFILE /usr/local/open-audit/"
            exit 1;
        fi
    fi
fi

if [ "$OSFLAVOUR" = "debian" ]; then
    if [ "$OS_MAJOR" -lt 11 ] ; then
        printBanner "Supported OS Warning"
        logmsg "The minimum supported version of Debian for Open-AudIT is 11, please upgrade your OS before attempting to install Open-AudIT."
        logmsg "The installer detected $OSFLAVOUR version $OS_MAJOR."
        if [ -n "$UNATTENDED" ]; then
            exit 1;
        fi
        if ! input_yn "Should I install anyway (y/n)? "; then
            execNoPrint "mv $LOGFILE /usr/local/open-audit/"
            exit 1;
        fi
    fi
fi

if [ "$OSFLAVOUR" = "ubuntu" ]; then
    if [ "$OS_MAJOR" -lt 20 ] ; then
        printBanner "Supported OS Warning"
        logmsg "The minimum supported version of Ubuntu for Open-AudIT is 20, please upgrade your OS before attempting to install Open-AudIT."
        logmsg "The installer detected $OSFLAVOUR version $OS_MAJOR."
        if [ -n "$UNATTENDED" ]; then
            exit 1;
        fi
        if ! input_yn "Should I install anyway (y/n)? "; then
            execNoPrint "mv $LOGFILE /usr/local/open-audit/"
            exit 1;
        fi
    fi
fi

if [ "$OSFLAVOUR" != "ubuntu" ] && [ "$OSFLAVOUR" != "debian" ] && [ "$OSFLAVOUR" != "redhat" ]; then
    printBanner "Supported OS Warning"
    logmsg "The supported distributions are Redhat, Debian and Ubuntu."
    logmsg "The installer detected $OSFLAVOUR version $OS_MAJOR."
    if [ -n "$UNATTENDED" ]; then
        exit 1;
    fi
    if ! input_yn "Should I install anyway (y/n)? "; then
        execNoPrint "mv $LOGFILE /usr/local/open-audit/"
        exit 1;
    fi
fi

# Install Ruby and Bundler (required for AssetSonar connector)
printBanner "Ruby Installation"
logmsg "Installing Ruby and Bundler for AssetSonar connector compatibility..."

# Check if Ruby is already installed and meets version requirements
if command -v ruby >/dev/null 2>&1; then
    ruby_version=$(ruby --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
    ruby_major=$(echo "$ruby_version" | cut -d. -f1)
    ruby_minor=$(echo "$ruby_version" | cut -d. -f2)
    logmsg "Ruby is already installed: version $ruby_version"

    # Check if version is at least 2.7
    if [ "$ruby_major" -gt 2 ] || ([ "$ruby_major" -eq 2 ] && [ "$ruby_minor" -ge 7 ]); then
        logmsg "Ruby version $ruby_version meets the minimum requirement (2.7+)."
    else
        logmsg "Ruby version $ruby_version is below the minimum requirement (2.7+). Installing newer version..."
        install_ruby=true
    fi
else
    logmsg "Ruby is not installed. Installing Ruby..."
    install_ruby=true
fi

# Install Ruby if needed
if [ "$install_ruby" = "true" ]; then
    if [ "$OSFLAVOUR" = "redhat" ]; then
        if [ "$OS_MAJOR" -ge 8 ]; then
            # For RHEL 8+, use dnf and enable EPEL for Ruby 2.7+
            execPrint "dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-$OS_MAJOR.noarch.rpm"
            execPrint "dnf -y install ruby ruby-devel rubygems"
        else
            # For older RHEL versions, try to get Ruby 2.7+ from SCL
            execPrint "yum -y install centos-release-scl"
            execPrint "yum -y install rh-ruby27 rh-ruby27-ruby-devel"
            # Enable SCL Ruby
            execPrint "scl enable rh-ruby27 bash -c 'echo \"source /opt/rh/rh-ruby27/enable\" >> /etc/profile.d/ruby.sh'"
        fi
    elif [ "$OSFLAVOUR" = "debian" ] || [ "$OSFLAVOUR" = "ubuntu" ]; then
        if [ "$OS_MAJOR" -ge 20 ] || [ "$OSFLAVOUR" = "debian" ] && [ "$OS_MAJOR" -ge 11 ]; then
            # For Ubuntu 20+ and Debian 11+, use standard packages (Ruby 2.7+)
            execPrint "apt-get update -qq 2>&1"
            execPrint "apt-get -yq -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install ruby ruby-dev rubygems"
        else
            # For older versions, add Brightbox PPA for Ruby 2.7
            execPrint "apt-get update -qq 2>&1"
            execPrint "apt-get -yq -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install software-properties-common"
            execPrint "apt-add-repository -y ppa:brightbox/ruby-ng"
            execPrint "apt-get update -qq 2>&1"
            execPrint "apt-get -yq -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install ruby2.7 ruby2.7-dev"
        fi
    fi

    # Verify installation
    if command -v ruby >/dev/null 2>&1; then
        ruby_version=$(ruby --version | grep -oE '[0-9]+\.[0-9]+' | head -1)
        ruby_major=$(echo "$ruby_version" | cut -d. -f1)
        ruby_minor=$(echo "$ruby_version" | cut -d. -f2)
        logmsg "Ruby installation successful: version $ruby_version"

        if [ "$ruby_major" -gt 2 ] || ([ "$ruby_major" -eq 2 ] && [ "$ruby_minor" -ge 7 ]); then
            logmsg "Ruby version $ruby_version meets the minimum requirement (2.7+)."
        else
            logmsg "ERROR: Ruby installation failed to meet version requirements."
            exit 1
        fi
    else
        logmsg "ERROR: Ruby installation failed."
        exit 1
    fi
fi

# Install Bundler if not already present
if ! command -v bundle >/dev/null 2>&1; then
    logmsg "Installing Bundler..."
    if [ "$OSFLAVOUR" = "redhat" ]; then
        execPrint "gem install bundler"
    elif [ "$OSFLAVOUR" = "debian" ] || [ "$OSFLAVOUR" = "ubuntu" ]; then
        execPrint "gem install bundler"
    fi

    # Verify bundler installation
    if command -v bundle >/dev/null 2>&1; then
        logmsg "Bundler installation successful."
    else
        logmsg "ERROR: Bundler installation failed."
        exit 1
    fi
else
    logmsg "Bundler is already installed."
fi

SELINUX_STATUS=$(getenforce 2>/dev/null)
HTTPD_T_STATUS=$(semanage permissive -l 2>/dev/null | grep httpd_t)
if [ -n "$SELINUX_STATUS" ]; then
    if [ "$SELINUX_STATUS" = "Permissive" ]; then
        logmsg "SELinux is enabled but in permissive mode."
    elif [ "$SELINUX_STATUS" = "Enforcing" ] && [ -z "$HTTPD_T_STATUS" ]; then
        printBanner "SELinux warning"
        logmsg "The installer has detected that SELinux is enabled on your system, and that it is set to enforce its policy and that there is no exception for httpd_t."
        logmsg "In this configuration it will prevent Open-AudIT from working. We recommend that you disable SELinux or at the very least, permit Apache in permissive mode."
        logmsg "See 'man 8 selinux' for details."

        if [ -n "$UNATTENDED" ] || input_yn "Should I set the Apache process in SELinux to permissive (y/n)? "; then
            execPrint "semanage permissive -a httpd_t 2>&1"
            HTTPD_T_STATUS=$(semanage permissive -l 2>/dev/null | grep httpd_t)
            if [ -z "$HTTPD_T_STATUS" ]; then
                logmsg "WARNING - Could not set HTTPD_T to permissive."
                logmsg "You as the system administrator will need to either disable SELinux or allow the HTTPD_T domain as permissive."
            fi
        fi

        if [ -z "$HTTPD_T_STATUS" ]; then
            input_text "Type CONTINUE to continue regardless of SELinux, or any other key to abort:"
            if [ "$RESPONSE" != "CONTINUE" ]; then
                logmsg "Aborting installation because of SELinux state.";
                execNoPrint "mv $LOGFILE /usr/local/open-audit/"
                exit 1;
            fi
        fi
    fi
fi

printBanner "Pre-requisites check and installation"

is_web_available=0
logmsg "Checking if Web is accessible."

# curl is available even on minimal centos install
if type curl >/dev/null 2>&1 && execNoPrint "curl --insecure -s -m 10 --retry 2 -o /dev/null https://services.opmantek.com/ping 2>/dev/null"; then
        logmsg "Web access is OK."
        is_web_available=1
fi

if [ "$is_web_available" -eq 0 ]; then
    if type wget >/dev/null 2>&1 && execNoPrint "wget --no-check-certificate -q -T 10 --tries=3 -O /dev/null https://services.opmantek.com/ping 2>/dev/null"; then
            logmsg "Web access is OK."
            is_web_available=1
    fi
fi

if [ "$is_web_available" -eq 0 ]; then
    logmsg "Your system cannot access the web, therefore $MGR will not
    be able to download any missing software packages. If any
    such missing packages are detected and you don't have
    a local source of packages (e.g. an installation DVD) then Open-AudIT
    will not run successfully.

    We recommend that you check our Wiki articles on working around
    package installation without Internet access in that case:

    https://community.opmantek.com/x/KQjcAg
    https://community.opmantek.com/x/boSG"
fi

# Get any existing PHP versions
php_version=$(php --version 2>/dev/null | grep "^PHP " | cut -d" " -f2)
php_major_version=$(echo "$php_version" | cut -d. -f1)
php_minor_version=$(echo "$php_version" | cut -d. -f2)

# Centos 8
if [ "$is_web_available" -eq 1 ] && [ "$OS_MAJOR" -eq 8 ] && [ "$OSFLAVOUR" = "redhat" ] && [ "$OS_ISCENTOS" -eq 1 ]; then
    if [ -n "$UNATTENDED" ] || input_yn "Enable the repositories and install packages (y/n)? "; then
        logmsg "Enabling Centos/Rocky/Alma optional RPM repo (please wait)."
        logmsg "Running dnf update."
        execPrint "dnf -y upgrade 2>&1"
        execPrint "dnf -y install yum-utils 2>&1"
        logmsg "Enabling optional RPM repo (please wait)."
        execPrint "dnf -y config-manager --set-enabled powertools 2>&1"
        execPrint "dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-$OS_MAJOR.noarch.rpm 2>&1"
        execPrint "dnf -y install https://rpms.remirepo.net/enterprise/remi-release-$OS_MAJOR.rpm 2>&1"
        logmsg "Installing any missing packages."
        execPrint "dnf -y module reset php 2>&1"
        execPrint "dnf -y module install php:remi-8.2 2>&1"
        execPrint "dnf -y install mariadb-server httpd php php-cli php-intl php-mysqlnd php-ldap php-mbstring php-process php-snmp php-sodium php-xml nmap zip curl wget sshpass screen samba-client logrotate perl-Time-ParseDate ipmitool net-snmp net-snmp-utils perl-Crypt-CBC libnsl libsodium 2>&1"
        # Redhat does not enable these servers by default
        logmsg "Ensuring MySQL and Apache are enabled and running"
        for srv in php-fpm mariadb httpd; do
            if type systemctl >/dev/null 2>&1; then
                execPrint "systemctl enable $srv"
            else
                execPrint "chkconfig $srv"
            fi;
        done
        # Start / Restart the servers
        execPrint "systemctl restart php-fpm >/dev/null 2>&1"
        execPrint "systemctl restart httpd >/dev/null 2>&1"
        execPrint "systemctl restart mariadb >/dev/null 2>&1"

    else
        logmsg "You will need to ensure you have installed a PHP version of at least 7.4 and the sodium php extension."
        logmsg "The required packages are: mariadb-server httpd php php-cli php-intl php-mysqlnd php-ldap php-mbstring php-process php-snmp php-sodium php-xml nmap zip curl wget sshpass screen samba-client logrotate perl-Time-ParseDate ipmitool net-snmp net-snmp-utils perl-Crypt-CBC libnsl libsodium"
    fi
fi
if [ "$OS_MAJOR" -eq 8 ] && [ "$OSFLAVOUR" = "redhat" ] && [ "$OS_ISCENTOS" -eq 1 ]; then
    # SUID on the nmap binary
    logmsg "Setting SUID on Nmap binary"
    execPrint "chmod u+s /usr/bin/nmap"
fi


# Centos 9
if [ "$is_web_available" -eq 1 ] && [ "$OS_MAJOR" -eq 9 ] && [ "$OSFLAVOUR" = "redhat" ] && [ "$OS_ISCENTOS" -eq 1 ]; then
    if [ -n "$UNATTENDED" ] || input_yn "Enable the repositories and install packages (y/n)? "; then
        logmsg "Enabling Centos/Rocky/Alma optional RPM repo (please wait)."
        execPrint "dnf -y upgrade 2>&1"
        execPrint "dnf -y install yum-utils 2>&1"
        execPrint "dnf -y config-manager --set-enabled crb 2>&1"
        execPrint "dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-$OS_MAJOR.noarch.rpm 2>&1"
        execPrint "/usr/bin/crb enable 2>&1"
        execPrint "dnf -y install https://rpms.remirepo.net/enterprise/remi-release-$OS_MAJOR.rpm 2>&1"
        execPrint "dnf -y module reset php 2>&1"
        execPrint "dnf -y module install php:remi-8.2 2>&1"
        execPrint "dnf -y upgrade 2>&1"
        execPrint "dnf -y install mariadb-server httpd php php-cli php-intl php-mysqlnd php-ldap php-mbstring php-process php-snmp php-sodium php-xml nmap zip curl wget sshpass screen samba-client logrotate perl-Time-ParseDate ipmitool net-snmp net-snmp-utils perl-Crypt-CBC libnsl libsodium 2>&1"
        if grep -qF Alma /etc/redhat-release; then
            # Install this package for Alma
            execPrint "dnf -y install libxcrypt-compat 2>&1"
        fi
        # Redhat does not enable these servers by default
        logmsg "Ensuring MySQL and Apache are enabled and running"
        for srv in php-fpm mariadb httpd; do
            if type systemctl >/dev/null 2>&1; then
                execPrint "systemctl enable $srv"
            else
                execPrint "chkconfig $srv"
            fi;
        done
        # Start / Restart the servers
        execPrint "systemctl restart php-fpm >/dev/null 2>&1"
        execPrint "systemctl restart httpd >/dev/null 2>&1"
        execPrint "systemctl restart mariadb >/dev/null 2>&1"
    else
        logmsg "You will need to ensure you have installed a PHP version of at least 7.4 and the sodium php extension."
        logmsg "The required packages are: mariadb-server httpd php php-cli php-intl php-mysqlnd php-ldap php-mbstring php-process php-snmp php-sodium php-xml nmap zip curl wget sshpass screen samba-client logrotate perl-Time-ParseDate ipmitool net-snmp perl-Crypt-CBC libnsl libsodium"
    fi
fi
if [ "$OS_MAJOR" -eq 9 ] && [ "$OSFLAVOUR" = "redhat" ] && [ "$OS_ISCENTOS" -eq 1 ]; then
    # SUID on the nmap binary
    logmsg "Setting SUID on Nmap binary"
    execPrint "chmod u+s /usr/bin/nmap"
fi


# RedHat 8 and 9
if [ "$is_web_available" -eq 1 ] && [ "$OS_MAJOR" -ge 8 ] && [ "$OSFLAVOUR" = "redhat" ] && [ "$OS_ISCENTOS" -ne 1 ]; then
    if [ -n "$UNATTENDED" ] || input_yn "Install required packages (y/n)? "; then
        if [ -n "$(rpm -qa remi-release)" ]; then
            logmsg "Removing external Remi repo and associated PHP packages."
            execPrint "dnf -y remove remi-release 2>&1"
            execPrint "dnf -y module reset php 2>&1"
            execPrint "dnf -y update 2>&1"
            execPrint "subscription-manager refresh 2>&1"
            execPrint "dnf -y remove php php-cli php-intl php-mysqlnd php-ldap php-mbstring php-process php-snmp php-sodium php-xml libsodium 2>&1"
        fi

        execPrint "subscription-manager repos --enable codeready-builder-for-rhel-$OS_MAJOR-$(arch)-rpms 2>&1"
        execPrint "dnf -y install https://dl.fedoraproject.org/pub/epel/epel-release-latest-$OS_MAJOR.noarch.rpm 2>&1"
        execPrint "/usr/bin/crb enable 2>&1"

        logmsg "Running dnf update."
        execPrint "dnf -y upgrade 2>&1"

        if [ "$OS_MAJOR" -eq 8 ]; then
            logmsg "Installing a suitable version of PHP (PHP 8.0)."
            execPrint "dnf -y module install php:8.0 --allowerasing"
        fi

        if [ "$OS_MAJOR" -eq 9 ]; then
            logmsg "Installing a suitable version of PHP (PHP 8.1)."
            execPrint "dnf -y module install php:8.1 --allowerasing"
        fi

        logmsg "Installing any missing packages."
        execPrint "dnf -y install --allowerasing curl httpd ipmitool libnsl logrotate mariadb-server net-snmp net-snmp-utils nmap perl-Crypt-CBC perl-Time-ParseDate php-intl php-ldap php-mysqlnd php-process php-snmp samba-client sshpass wget zip 2>&1"
        # Redhat does not enable these servers by default
        logmsg "Ensuring MySQL and Apache are enabled and running"
        for srv in php-fpm mariadb httpd; do
            if type systemctl >/dev/null 2>&1; then
                execPrint "systemctl enable $srv"
            else
                execPrint "chkconfig $srv"
            fi;
        done
        # Start / Restart the servers
        execPrint "systemctl restart php-fpm >/dev/null 2>&1"
        execPrint "systemctl restart httpd >/dev/null 2>&1"
        execPrint "systemctl restart mariadb >/dev/null 2>&1"
    fi
fi
if [ "$OS_MAJOR" -ge 8 ] && [ "$OSFLAVOUR" = "redhat" ] && [ "$OS_ISCENTOS" -ne 1 ]; then
    # SUID on the nmap binary
    logmsg "Setting SUID on Nmap binary"
    execPrint "chmod u+s /usr/bin/nmap"

    # Configure the firewall
    firewall_status=$(firewall-cmd --state 2>/dev/null)
    zone=$(firewall-cmd --get-default-zone 2>/dev/null)
    http_status="denied"
    if [ -n "$(firewall-cmd --list-all --zone=$zone 2>/dev/null | grep services: | grep http)" ]; then
        http_status="allowed"
    fi
    logmsg "INFO - Firewall status is $firewall_status. Firewall zone is: $zone. HTTP is $http_status."
    if [ "$firewall_status" = "running" ] && [ "$http_status" = "denied" ]; then
        if [ -n "$UNATTENDED" ] || input_yn "Should we allow port 80 through the firewall in the $zone zone (y/n)? "; then
            execPrint "firewall-cmd --zone=$zone --add-service=http --permanent"
            execPrint "firewall-cmd --reload"
        fi
    fi
fi


# Ubuntu 20, 22, 24
if [ "$is_web_available" -eq 1 ] && [ "$OS_MAJOR" -ge 20 ] && [ "$OSFLAVOUR" = "ubuntu" ]; then
    if [ -n "$UNATTENDED" ] || input_yn "Install packages (y/n)? "; then
        execPrint "apt-get update -qq 2>&1"
        execPrint "apt-get -yq -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install mariadb-server apache2 apache2-utils libapache2-mod-php openssh-client php php-cli php-curl php-intl php-ldap php-mbstring php-mysql php-snmp php-xml nmap zip wget curl sshpass screen smbclient logrotate ipmitool snmp libcrypt-cbc-perl 2>&1"
        # Start / Restart the servers
        execPrint "systemctl restart apache2 >/dev/null 2>&1"
        execPrint "systemctl restart mysql >/dev/null 2>&1"
    else
        logmsg "You will need to ensure you have installed a PHP version of at least 7.4 and the sodium php extension."
        logmsg "The required packages are: mariadb-server apache2 apache2-utils libapache2-mod-php openssh-client php php-cli php-curl php-intl php-ldap php-mbstring php-mysql php-snmp php-xml nmap zip wget curl sshpass screen smbclient logrotate ipmitool snmp libcrypt-cbc-perl"
    fi
fi
if [ "$OS_MAJOR" -ge 20 ] && [ "$OSFLAVOUR" = "ubuntu" ]; then
    # SUID on the nmap binary
    execPrint "chmod u+s /usr/bin/nmap"
    execPrint "dpkg-statoverride --update --add root root 4755 /usr/bin/nmap"
fi


# Debian 11, 12
if [ "$is_web_available" -eq 1 ] && [ "$OS_MAJOR" -ge 11 ] && [ "$OSFLAVOUR" = "debian" ]; then
    if [ -n "$UNATTENDED" ] || input_yn "Install packages (y/n)? "; then
        execPrint "apt-get update -qq 2>&1"
        execPrint "apt-get -yq -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold install mariadb-server apache2 apache2-utils libapache2-mod-php openssh-client php php-cli php-curl php-intl php-ldap php-mbstring php-mysql php-snmp php-xml nmap zip wget curl sshpass screen smbclient logrotate ipmitool snmp libcrypt-cbc-perl 2>&1"
        # Start / Restart the servers
        execPrint "systemctl restart apache2 >/dev/null 2>&1"
        execPrint "systemctl restart mysql >/dev/null 2>&1"
    else
        logmsg "You will need to ensure you have installed a PHP version of at least 7.4 and the sodium php extension."
        logmsg "The required packages are: mariadb-server apache2 apache2-utils libapache2-mod-php openssh-client php php-cli php-curl php-intl php-ldap php-mbstring php-mysql php-snmp php-xml nmap zip wget curl sshpass screen smbclient logrotate ipmitool snmp libcrypt-cbc-perl"
    fi
fi
if [ "$OS_MAJOR" -ge 11 ] && [ "$OSFLAVOUR" = "debian" ]; then
    # SUID on the nmap binary
    execPrint "chmod u+s /usr/bin/nmap"
    execPrint "dpkg-statoverride --update --add root root 4755 /usr/bin/nmap"
fi


php_version=$(php --version | grep "^PHP " | cut -d" " -f2)
php_major_version=$(echo "$php_version" | cut -d. -f1)
php_minor_version=$(echo "$php_version" | cut -d. -f2)
if [ "$php_major_version" -lt 7 ]; then
    logmsg "WARNING - Your PHP is version $php_version. Open-AudIT requires a minimum PHP of 7.4. Exiting."
    exit 1
fi
if [ "$php_major_version" -eq 7 ] && [ "$php_minor_version" -lt 4 ]; then
    logmsg "WARNING - Your PHP is version $php_version. Open-AudIT requires a minimum PHP of 7.4. Exiting."
    exit 1
fi
logmsg "INFO - Your PHP is version $php_version. Open-AudIT requires a minimum PHP of 7.4. You are good to go."


tmpstatus=$(grep ' /tmp ' /proc/mounts 2>/dev/null | grep noexec)
if [ -n "$tmpstatus" ]; then
    logmsg "Your /tmp is mounted noexec. Open-AudIT requires /tmp to be writable. Exiting."
    if [ -n "$UNATTENDED" ] || input_yn "Install anyway (y/n)? "; then
        logmsg "Installing even though /tmp detected as noexec."
    else
        logmsg "Halting install as per user request."
        exit 1
    fi
else
    logmsg "INFO - /tmp not mounted noexec, continuing."
fi

datetime=$(date +%Y%m%d%H%M%S)
TARGETDIR="/usr/local/open-audit"
BACKUPDIR="/usr/local/open-audit-backup-$datetime"
status_existing=""

if [ "$status" = "upgrade" ]; then
    printBanner "Backing up existing files and database"
    # Move existing install into the backup directory
    logmsg "Backing up /usr/local/open-audit to $BACKUPDIR"
    execPrint "mv /usr/local/open-audit $BACKUPDIR"

    # Retrieve the 'old' (pre 5) or 'new' (post 5) status of the existing install
    status_existing="new"
    if [ -f "$BACKUPDIR/code_igniter/application/config/database.php" ]; then
        logmsg "Upgrading pre v5.0.0."
        status_existing="old"
        hostname=$(grep "db\['default'\]\['hostname'\]" "$BACKUPDIR/code_igniter/application/config/database.php" | head -n1 | cut -d\" -f2)
        username=$(grep "db\['default'\]\['username'\]" "$BACKUPDIR/code_igniter/application/config/database.php" | head -n1 | cut -d\" -f2)
        password=$(grep "db\['default'\]\['password'\]" "$BACKUPDIR/code_igniter/application/config/database.php" | head -n1 | cut -d\" -f2)
        database=$(grep "db\['default'\]\['database'\]" "$BACKUPDIR/code_igniter/application/config/database.php" | head -n1 | cut -d\" -f2)
    fi
    if [ "$status_existing" = "new" ]; then
        logmsg "Upgrading post 5.0.0"
        hostname=$(grep hostname "$BACKUPDIR/app/Config/Database.json" 2>/dev/null | cut -d\" -f4)
        username=$(grep username "$BACKUPDIR/app/Config/Database.json" 2>/dev/null | cut -d\" -f4)
        password=$(grep password "$BACKUPDIR/app/Config/Database.json" 2>/dev/null | cut -d\" -f4)
        database=$(grep database "$BACKUPDIR/app/Config/Database.json" 2>/dev/null | cut -d\" -f4)
    fi
    # Backup the database
    if [ -z "$hostname" ] || [ -z "$username" ] || [ -z "$password" ] || [ -z "$database" ]; then
        logmsg "Upgrade detected, but cannot read database credentials, restoring files."
        execPrint "mv $BACKUPDIR /usr/local/open-audit"
        if [ -f "/usr/local/open-audit/code_igniter/application/config/database.php" ]; then
            logmsg "Database credentials should be readable in the file /usr/local/open-audit/code_igniter/application/config/database.php"
            logmsg "To check, run the below command:"
            logmsg "grep \"db\['default'\]\['username'\]\" \"/usr/local/open-audit/code_igniter/application/config/database.php\" | head -n1 | cut -d\\\" -f2"
        fi
        if [ -f "/usr/local/open-audit/app/Config/Database.json" ]; then
            logmsg "Database credentials should be readable in the file /usr/local/open-audit/app/Config/Database.json"
            logmsg "To check, run the below command:"
            logmsg "grep username \"usr/local/open-audit/app/Config/Database.json\" | head -n1 | cut -d\\\" -f2"
        fi
        execNoPrint "mv $LOGFILE /usr/local/open-audit/"
        exit 1
    fi
    logmsg "Backing up database to $BACKUPDIR/open-audit-backup.sql."
    logmsg "mysqldump -u $username -pREMOVED -h $hostname $database > $BACKUPDIR/open-audit-backup.sql"
    mysqldump -u "$username" -p"$password" -h "$hostname" "$database" > "$BACKUPDIR"/open-audit-backup.sql
fi

if ! execPrint "mkdir -p $TARGETDIR"; then
    logmsg "Cannot create $TARGETDIR, reverting backup"
    execPrint "mv $BACKUPDIR $TARGETDIR"
    execNoPrint "mv $LOGFILE /usr/local/open-audit/"
    exit 1
fi

printBanner "Installing Open-AudIT files"

# Move these (possibly pre 5.0.0) directories
if [ -d "/var/www/html/open-audit" ] && [ ! -L "/var/www/html/open-audit" ]; then
    execPrint "mv /var/www/html/open-audit $BACKUPDIR/www.old"
    logmsg "Moving /var/www/html/open-audit to $BACKUPDIR/www.old"
fi
if [ -d "/var/www/open-audit" ] && [ ! -L "/var/www/open-audit" ]; then
    execPrint "mv /var/www/open-audit /var/www/open-audit.old"
    execPrint "mv /var/www/open-audit $BACKUPDIR/www.old"
    logmsg "Moving /var/www/open-audit to $BACKUPDIR/www.old"
fi

# Copy the files
execPrint "cp -far ./* $TARGETDIR"

# permissions
execPrint "chmod 0660 $TARGETDIR/app/Config/OpenAudit.php"
execPrint "chmod 0777 $TARGETDIR/other/scripts"
execPrint "chmod 0777 $TARGETDIR/other/ssg-results"
execPrint "chmod 0777 $TARGETDIR/public/ssg-definitions"
execPrint "chmod -R 777 $TARGETDIR/app/Attachments"
execPrint "chmod -R 777 $TARGETDIR/public/custom_images"
execPrint "chmod 0440 $TARGETDIR/app/Config/*.php"
execPrint "chmod -R 777 $TARGETDIR/writable"
execPrint "chmod 0666 $TARGETDIR/app/Views/lang/*.inc"

if [ "$status" = "upgrade" ]; then
    if [ "$status_existing" = "old" ]; then
        logmsg "Copying pre-5.0.0 attachments and custom images."
        # Move our pre-5.0.0 attachments
        execPrint cp $BACKUPDIR/code_igniter/application/attachments/* $TARGETDIR/app/Attachments/
        # Copy our custom images
        execPrint cp $BACKUPDIR/www/open-audit/custom_images/* $TARGETDIR/public/custom_images/
        # Add the new credentials
        logmsg "Creating database credentials file."
        sed -i -e "s|\"hostname\": \"127.0.0.1\"|\"hostname\": \"$hostname\"|" /usr/local/open-audit/app/Config/Database.json
        sed -i -e "s|\"database\": \"127.0.0.1\"|\"openaudit\": \"$database\"|" /usr/local/open-audit/app/Config/Database.json
        sed -i -e "s|\"username\": \"127.0.0.1\"|\"openaudit\": \"$username\"|" /usr/local/open-audit/app/Config/Database.json
        sed -i -e "s|\"password\": \"127.0.0.1\"|\"openauditpassword\": \"$password\"|" /usr/local/open-audit/app/Config/Database.json
    fi
    if [ "$status_existing" = "new" ]; then
        logmsg "Copying attachments and custom images."
        # Copy our post-5.0.0 attachments
        execPrint cp $BACKUPDIR/app/Attachments/* $TARGETDIR/app/Attachments/
        # Copy our custom images
        execPrint cp $BACKUPDIR/public/custom_images/* $TARGETDIR/public/custom_images/
        logmsg "Restoring database credentials file."
        # Copy the Database credentials file
        execPrint cp $BACKUPDIR/app/Config/Database.json $TARGETDIR/app/Config/Database.json
    fi

fi

if [ "$OSFLAVOUR" = "redhat" ]; then
		WWWGRP="apache"
elif [ "$OSFLAVOUR" = "debian" ] || [ "$OSFLAVOUR" = "ubuntu" ]; then
		WWWGRP="www-data"
fi

# default to old-style standard webroot, unless the newer flavour exists
WWWTARGETDIR=/var/www
[ -d "/var/www/html" ] && WWWTARGETDIR=/var/www/html

execPrint "chown -R $WWWGRP:$WWWGRP $TARGETDIR"

logmsg "Copying Open-AudIT Web files"

execPrint "ln -s /usr/local/open-audit/public $WWWTARGETDIR/open-audit"

execPrint "chown -h $WWWGRP:$WWWGRP $WWWTARGETDIR/open-audit"

# Only replace the default index.html if it's the boring 'it works' debian placeholder
if [ "$OSFLAVOUR" = "debian" ] || [ "$OSFLAVOUR" = "ubuntu" ] && grep -q "It works" $WWWTARGETDIR/index.html 2>/dev/null; then
    mv -f $WWWTARGETDIR/index.html $WWWTARGETDIR/index.html.boilerplate;
    cp /usr/local/open-audit/public/index.html.default $WWWTARGETDIR/index.html
fi

if [ "$status" = "install" ]; then
    printBanner "Open-AudIT Database Setup"
    if ! mysql -u root -e 'exit' >/dev/null 2>&1; then
        if [ -z "$UNATTENDED" ]; then
            # ask the user for the MySQL root password
            echo "We require the MySQL root user credentials to create the database and user."
            while true; do
                input_text "Enter the MySQL root user's password:"
                root_password="$RESPONSE"
                if mysql -u root -e 'exit' >/dev/null 2>&1; then
                    break;
                fi
                echo "The MySQL root password is incorrect. Please re-enter it."
            done
        else
            logmsg "Unattended mode specified but MySQL root uses a password, exiting."
            logmsg "You will need to create the database and user manually."
            execNoPrint "mv $LOGFILE /usr/local/open-audit/"
            exit 1;
        fi
    fi

    # execPrint and mysql -e are not happy together
    # see common_functions.sh echologVerboseError function use in mysql commands further below
    #	for a mechanism to log errors as execPrint does
    #	this approach will work: its the 'eval' in execPrint that breaks 'mysql -e'
    #	see: https://stackoverflow.com/questions/1636977/store-mysql-query-output-into-a-shell-variable

    # complain about/offer to change a blank mysql password if and only if in interactive mode
    if [ -z "$root_password" ] && [ -z "$UNATTENDED" ]; then
        logmsg "Your MySQL root password is blank."
        if input_yn "Should I set the default Open-AudIT root password to 'openauditrootuserpassword' (y/n)? "; then
            logmsg "Setting the MySQL root password to 'openauditrootuserpassword'";
            root_password="openauditrootuserpassword"
            RES=0;
            unset OUTPUT;
            OUTPUT="$(mysql -u root -e "USE mysql; SET PASSWORD FOR 'root'@'localhost' = password('$root_password'); FLUSH PRIVILEGES;" 2>&1)"||RES=$?;
            # echologVerboseError expects parameters: COMMAND (as a string '$*' or '...', not an array '$@'), EXITCODE then COMMANDOUTPUT
            # if command succeeded RES is unset, so default 0
            # if command failed we may not have OUTPUT, so default ""
            if [ "$RES" != 0 ]; then
                logmsg "mysql -u root -e \"USE mysql; SET PASSWORD FOR 'root'@'localhost' = password('$root_password'); FLUSH PRIVILEGES;\" 2>&1" \
                    "${RES}" \
                    "${OUTPUT:-}";
                # attempt again using new format
                RES=0;
                unset OUTPUT;
                OUTPUT="$(mysql -u root -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$root_password'; FLUSH PRIVILEGES;" 2>&1)"||RES=$?;
                if [ "$RES" != 0 ]; then
                    logmsg "mysql -u root -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '$root_password'; FLUSH PRIVILEGES;\" 2>&1" \
                        "${RES}" \
                        "${OUTPUT:-}";
                    echo "WARNING - Could not set the password for the MySQL root user. You will have to do this manually."
                fi
            fi
        else
            logmsg "Not updating the blank MySQL root password as instructed."
        fi
    fi

    printBanner "Creating the Open-AudIT database and MySQL Open-AudIT user."

    RES=0;
    unset OUTPUT;
    if [ -n "$root_password" ]; then
        OUTPUT="$(mysql -u root -p$root_password -e "CREATE DATABASE openaudit;" 2>&1)"||RES=$?;
        logmsg "mysql -u root -pREMOVED -e \"CREATE DATABASE openaudit; 2>&1\"" \
        "${RES}" \
        "${OUTPUT:-}";
    else
        OUTPUT="$(mysql -u root -e "CREATE DATABASE openaudit;" 2>&1)"||RES=$?;
        logmsg "mysql -u root -e \"CREATE DATABASE openaudit; 2>&1\"" \
        "${RES}" \
        "${OUTPUT:-}";
    fi

    if [ "$RES" != 0 ]; then
        printBanner "Database Warning"
        logmsg "WARNING - Could not create the openaudit database. You will have to do this manually."
        if input_yn "Type y to continue (y/n)? "; then
            logmsg "Continuing"
        else
            logmsg "Exiting"
            logmsg "You will need to revert the /usr/local changes."
            logmsg "Move /usr/local/open-audit to /usr/local/open-audit.bad"
            logmsg "Move $BACKUPDIR to /usr/local/open-audit."
            logmsg "Move /usr/local/open-audit/www.old back to its original place (either /var/www or /var/www/html)."
            execNoPrint "mv $LOGFILE /usr/local/open-audit/"
            exit 1;
        fi
    fi

    RES=0;
    unset OUTPUT;
    OUTPUT="$(mysql -u root -p$root_password -e "CREATE USER openaudit@localhost IDENTIFIED BY 'openauditpassword';" 2>&1)"||RES=$?;
    # echologVerboseError expects parameters: COMMAND (as a string '$*' or '...', not an array '$@'), EXITCODE then COMMANDOUTPUT
    # if command succeeded RES is unset, so default 0
    # if command failed we may not have OUTPUT, so default ""
    logmsg "mysql -u root -pREMOVED -e \"CREATE USER openaudit@localhost IDENTIFIED BY 'openauditpassword';\" 2>&1" \
                "${RES}" \
                "${OUTPUT:-}";
    if [ "$RES" != 0 ]; then
        logmsg "WARNING - Could not create the openaudit MySQL user. You will have to do this manually."
    fi

    RES=0;
    unset OUTPUT;
    if [ -n "$root_password" ]; then
        OUTPUT="$(mysql -u root -p$root_password -e "GRANT ALL PRIVILEGES ON openaudit.* TO openaudit@localhost IDENTIFIED BY 'openauditpassword'; FLUSH PRIVILEGES;" 2>&1)"||RES=$?;
    else
        OUTPUT="$(mysql -u root -e "GRANT ALL PRIVILEGES ON openaudit.* TO openaudit@localhost IDENTIFIED BY 'openauditpassword'; FLUSH PRIVILEGES;" 2>&1)"||RES=$?;
    fi
    if [ "$RES" != 0 ]; then
        if [ -n "$root_password" ]; then
            logmsg "mysql -u root -pREMOVED -e \"GRANT ALL PRIVILEGES ON openaudit.* TO openaudit@localhost IDENTIFIED BY 'openauditpassword'; FLUSH PRIVILEGES;\" 2>&1" \
                "${RES}" \
                "${OUTPUT:-}";
        else
            logmsg "mysql -u root -e \"GRANT ALL PRIVILEGES ON openaudit.* TO openaudit@localhost IDENTIFIED BY 'openauditpassword'; FLUSH PRIVILEGES;\" 2>&1" \
                "${RES}" \
                "${OUTPUT:-}";
        fi
        RES=0;
        unset OUTPUT;
        if [ -n "$root_password" ]; then
            OUTPUT="$(mysql -u root -p$root_password -e "GRANT ALL PRIVILEGES ON openaudit.* TO openaudit@localhost; FLUSH PRIVILEGES;" 2>&1)"||RES=$?;
        else
            OUTPUT="$(mysql -u root -e "GRANT ALL PRIVILEGES ON openaudit.* TO openaudit@localhost; FLUSH PRIVILEGES;" 2>&1)"||RES=$?;
        fi
        if [ "$RES" != 0 ]; then
            if [ -n "$root_password" ]; then
                logmsg "mysql -u root -pREMOVED -e \"GRANT ALL PRIVILEGES ON openaudit.* TO openaudit@localhost; FLUSH PRIVILEGES;\" 2>&1" \
                "${RES}" \
                "${OUTPUT:-}";
            else
                logmsg "mysql -u root -e \"GRANT ALL PRIVILEGES ON openaudit.* TO openaudit@localhost; FLUSH PRIVILEGES;\" 2>&1" \
                "${RES}" \
                "${OUTPUT:-}";
            fi
            echo "WARNING - Could not grant access to openaudit MySQL user. You will have to do this manually."
        fi
    fi

    logmsg "Preparing the Open-AudIT database.";

    RES=0;
    unset OUTPUT;
    if [ -n "$root_password" ]; then
        OUTPUT="$(mysql -u root -p$root_password openaudit -e "source $TARGETDIR/other/open-audit.sql" 2>&1)"||RES=$?;
    else
        OUTPUT="$(mysql -u root openaudit -e "source $TARGETDIR/other/open-audit.sql" 2>&1)"||RES=$?;
    fi
    # echologVerboseError expects parameters: COMMAND (as a string '$*' or '...', not an array '$@'), EXITCODE then COMMANDOUTPUT
    # if command succeeded RES is unset, so default 0
    # if command failed we may not have OUTPUT, so default ""
    if [ -n "$root_password" ]; then
        logmsg "mysql -u root -pREMOVED openaudit -e \"source $TARGETDIR/other/open-audit.sql\" 2>&1" \
        "${RES}" \
        "${OUTPUT:-}";
    else
        logmsg "mysql -u root openaudit -e \"source $TARGETDIR/other/open-audit.sql\" 2>&1" \
        "${RES}" \
        "${OUTPUT:-}";
    fi
    if [ "$RES" != 0 ]; then
        logmsg "WARNING - Could not populate openaudit database. You will need to do this manually."
    fi

else
    logmsg "Upgrade of existing Open-AudIT installation, no database initialisation required."

    # We need to copy any Baselines Results files to where www-data can read them (cannot read/usr/local/omk/var as it's root only).
    if [ -n "$(ls -A /usr/local/omk/var/oae/baselines/results 2>/dev/null)" ]; then
        logmsg "Moving Baselines Results to a directoy the Apache user can read."
        if [ ! -d "/usr/local/open-audit/temp_baselines_results" ]; then
            execPrint mkdir /usr/local/open-audit/temp_baselines_results||:;
        fi
        execPrint mv /usr/local/omk/var/oae/baselines/results/*.json /usr/local/open-audit/temp_baselines_results/||:;
        execPrint chmod -R 777 /usr/local/open-audit/temp_baselines_results||:;
        execPrint chown -R $WWWGRP:$WWWGRP /usr/local/open-audit/temp_baselines_results||:;
    fi
fi

# Change opModules.json
if [ -f "/usr/local/omk/bin/patch_config.exe" ]; then
    logmsg "Update opModules.json to point to the correct Open-AudIT install."
    execPrint "/usr/local/omk/bin/patch_config.exe -b /usr/local/omk/conf/opModules.json /oae/name=Open-AudIT /oae/link=/open-audit/index.php /oae/base=/usr/local/open-audit /oae/file=/app/Config/OpenAudit.php 2>&1"||:;
    # Remove from opCommon.json
    logmsg "Remove Open-AudIT from load_applications in opConfig.json"
    execPrint "/usr/local/omk/bin/patch_config.exe -b /usr/local/omk/conf/opCommon.json /omkd/load_applications-=Open-AudIT 2>&1"||:;
    logmsg "Restarting the omkd daemon to load changed configuration"
    execPrint "systemctl restart omkd"
    printBanner "Warning"
    logmsg "Open-AudIT may not appear on the /omk Welcome page until such time as another application (not Open-AudIT) has been updated."
    logmsg ""
    logmsg "Open-AudIT will appear in the Modules menu item immediately regardless of installing another FirstWave application."
    logmsg ""
    logmsg "You should update any of your bookmarks from http://<HOSTNAME_OR_IP>/omk/open-audit to http://<HOSTNAME_OR_IP>/open-audit"
    logmsg ""
    if [ -z "$UNATTENDED" ]; then
        input_yn "Type y to continue (y)? "
    fi
fi

printBanner "Setting up Open-AudIT Scheduling"
if [ -f /etc/cron.d/open-audit ]; then
    logmsg "Open-AudIT cron file exists, moving to /usr/local/open-audit/cron.d.open-audit. If you have changed this file, you will need to update the new cron.d openaudit file."
    execPrint mv /etc/cron.d/open-audit /usr/local/open-audit/cron.d.open-audit
fi

if [ ! -f /etc/cron.d/open-audit ]; then
    # Setup a new cron
    cat >/etc/cron.d/open-audit <<EOF
# m h dom month dow user command

# run the task checker each minute
* * * * *	root	php /usr/local/open-audit/public/index.php tasks execute >/dev/null 2>&1

EOF
fi

# if [ "$is_web_available" -eq 1 ]; then
#     if [ "$status" = "install" ]; then
#         username="openaudit"
#         password="openauditpassword"
#         database="openaudit"
#         hostname="localhost"
#     fi
#     uuid=`mysql -u "$username" -p$password -h "$hostname" "$database" -e "SELECT value FROM configuration WHERE name = 'uuid'"` | grep -v ^+ | grep -v ^value

#     license=`/usr/local/open-audit/other/enterprise.bin --license`

#     timezone=""
#     if [ "$OSFLAVOUR" = "redhat" ]; then
#         if [ -f "/etc/sysconfig/clock" ]; then
#             timezone=`cat /etc/sysconfig/clock | grep ZONE | cut -d"\"" -f2 2>/dev/null`
#         fi
#         if [ "$timezone" = "" ]; then
#             timezone=`timedatectl 2>/dev/null | grep zone | cut -d: -f2 | cut -d"(" -f1`
#         fi

#     fi
#     if [ "$OSFLAVOUR" = "debian" ] || [ "$OSFLAVOUR" = "ubuntu" ]; then
#         timezone=`cat /etc/timezone`
#     fi

#     OSFLAVOR="${OSFLAVOR^}"
#     os="$OSFLAVOUR $OS_MINOR.$OS_MINOR"
#     products="[\"Open-AudIT\""
#     if [ -f "/usr/local/omk/lib/AddressController.pm.exe" ]; then
#         products="$products ,\"opAddress\""
#     fi
#     if [ -f "/usr/local/omk/lib/ChartsController.pm.exe" ]; then
#         products="$products ,\"opCharts\""
#     fi
#     if [ -f "/usr/local/omk/lib/EventsController.pm.exe" ]; then
#         products="$products ,\"opEvents\""
#     fi
#     if [ -f "/usr/local/omk/lib/FlowController.pm.exe" ]; then
#         products="$products ,\"opFlow\""
#     fi
#     if [ -f "/usr/local/omk/lib/HighAvailabilityController.pm.exe" ]; then
#         products="$products ,\"opHA\""
#     fi
#     if [ -f "/usr/local/omk/lib/ReportsController.pm.exe" ]; then
#         products="$products ,\"opReports\""
#     fi
#     products="$products]"

#     curl --insecure -s -m 10 --retry 2 -o /dev/null --data-urlencode "uuid=$UUID" --data-urlencode "server_os=Linux" --data-urlencode "server_platform=$os" --data-urlencode "product=Open-AudIT" --data-urlencode "action=$status" --data-urlencode "version=$VERSION" --data-urlencode "server_timezone=$timezone" --data-urlencode "license=$license" --data-urlencode "products=$products" https://example.com/form/ 2>/dev/null
# fi


# an initial install of this product
if [ "$status" = "install" ]; then
		printBanner "Open-AudIT has been installed"

		logmsg "This initial installation of Open-AudIT is now complete.

However, to configure and fine-tune the application suitably for
your environment you will need to make certain configuration adjustments.

We highly recommend that you visit the documentation site for Open-AudIT at

https://community.opmantek.com/display/OA/Home

which will help you to determine any configuration changes
that may be required for your environment."

else
	printBanner "Open-AudIT has been upgraded"

    logmsg "Your Open-AudIT installation has now been upgraded.

You will find more information in the release notes at

https://community.opmantek.com/display/OA/Release+Notes+for+Open-AudIT+v$VERSION"

fi

printBanner "All Done!"

logmsg "Open-AudIT should now be accessible at

http://<HOSTNAME_OR_IP>/open-audit/index.php

Check your firewall(s).

FirstWave applications will require network connectivity to devices to collect data
as well as users connecting to the server to access the WEB GUI.

Please check any locally running firewall logs as well as network firewalls
if you are having any issues with connectivity.

You may also want to SHIFT+reload your browser page to make sure it retrieves the latest CSS and JS files.

We hope you find Open-AudIT as useful as we do."

execNoPrint "mv $LOGFILE /usr/local/open-audit/"

if [ "$SELINUX_STATUS" = "Enforcing" ] && [ -z "$HTTPD_T_STATUS" ]; then
    logmsg "And one more thing: SELINUX IS ENFORCING with NO Apache exception."
    logmsg "Don't forget to disable SELinux or allow an exception for Apache."
fi

