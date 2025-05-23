#!/bin/bash
set -ex
BINDIR=`dirname $0`
source $BINDIR/common.sh

sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 10.45.0.0/16 ! -o ogstun -j MASQUERADE

if [ -f $SRCDIR/open5gs-setup-complete ]; then
    echo "setup already ran; not running again"
    exit 0
fi

sudo apt update
sudo apt install -y software-properties-common gnupg
sudo add-apt-repository -y ppa:open5gs/latest
sudo add-apt-repository -y ppa:wireshark-dev/stable
echo "wireshark-common wireshark-common/install-setuid boolean false" | sudo debconf-set-selections
curl -fsSL https://pgp.mongodb.com/server-6.0.asc | \
    sudo gpg -o /usr/share/keyrings/mongodb-server-6.0.gpg --dearmor
echo "deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-6.0.gpg ] https://repo.mongodb.org/apt/ubuntu $(lsb_release -cs)/mongodb-org/6.0 multiverse" | \
    sudo tee /etc/apt/sources.list.d/mongodb-org-6.0.list
sudo apt update
sudo apt install -y \
    mongodb-org \
    mongodb-mongosh \
    iperf3 \
    tshark \
    wireshark

sudo systemctl start mongod
sudo systemctl enable mongod
sudo apt install -y open5gs
sudo cp /local/repository/etc/open5gs/* /etc/open5gs/

sudo systemctl restart open5gs-mmed
sudo systemctl restart open5gs-sgwcd
sudo systemctl restart open5gs-smfd
sudo systemctl restart open5gs-amfd
sudo systemctl restart open5gs-sgwud
sudo systemctl restart open5gs-upfd
sudo systemctl restart open5gs-hssd
sudo systemctl restart open5gs-pcrfd
sudo systemctl restart open5gs-nrfd
sudo systemctl restart open5gs-ausfd
sudo systemctl restart open5gs-udmd
sudo systemctl restart open5gs-pcfd
sudo systemctl restart open5gs-nssfd
sudo systemctl restart open5gs-bsfd
sudo systemctl restart open5gs-udrd

# change default logrotate settings to weekly and allow reading by anyone (promtail)
cat <<EOF >> /tmp/open5gs-logrotate
/var/log/open5gs/*.log {
    weekly
    sharedscripts
    missingok
    compress
    rotate 14
    create 644 open5gs open5gs

    postrotate
        for i in nrfd scpd pcrfd hssd ausfd udmd udrd upfd sgwcd sgwud smfd mmed amfd; do
            systemctl reload open5gs-$i
        done
    endscript
}
EOF
sudo mv /tmp/open5gs-logrotate /etc/logrotate.d/open5gs

cd $SRCDIR
wget https://raw.githubusercontent.com/open5gs/open5gs/main/misc/db/open5gs-dbctl
chmod +x open5gs-dbctl
for imsi in {100..150}; do
    ./open5gs-dbctl add_ue_with_slice 999990000000$imsi 00112233445566778899aabbccddeeff 0ed47545168eafe2c39c075829a7b61f internet 1 000001 # IMSI,K,OPC
    ./open5gs-dbctl type 999990000000$imsi 1  # APN type IPV4
done
touch $SRCDIR/open5gs-setup-complete
