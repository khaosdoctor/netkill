# NetKill

> Kills the Internet connection of certain devices in a LAN using ARP Spoofing

# Why I did this

Because I have ADHD. So It's **EXTREMELY** difficult to focus, especially when
you have multiple sources of distractions. In my case, cellphones and others. So
I took a wild turn and said "I'll make it impossible for me to access the
Internet", just like my parents used to do with me when I was super addicted as
a child.

However, there's no "easy" way to do this, there are easier ways to cut the
Internet of an entire LAN, but this is not what I want because I do have other
machines that need to be plugged in at all times. Also, I don't want to kill the
signal every day, just a handful of days a week, for some specific times.

The idea came from [this post](https://community.home-assistant.io/t/cut-internet-temporarily-in-a-device-in-your-lan/20000) in the Home Assistant forum.

### Current solutions

If you have total control of your network, you can try things like these:

1. _Router-level parental blocking:_ Possible in multiple routers, not in mine.
   You'd have to pay to have advanced parental controls (F\* you TP-Link).
2. _DNS-level blocking:_ Kinda works, you can use PiHole or Adguard Home to
   create a DNS sinkhole at specific days of the week where all traffic from
   specific clients are just discarded. However, they don't have automations for
   that and you'd need to automate curl requests, which sucks. Plus, DNS blocking
   won't stop you from accessing every service (some P2P or socket services still
   works if they're already connected). Plus again, it's super easy to set another
   DNS service and bypass this.
3. _Firewall blocking_: If you have a LAN-wide firewall you could, in theory,
   block a client. This can be automated but I didn't have a LAN-wide solution
   specific for this, neither did I want to manually set my own

Overall, there's no _good_ way to do this, not even this script. Killing the
Internet signal from a specific device seamlessly, without interaction and
without any device input **is** and will **always** be hacky.

## How does this work

> If you just want to install everything you can skip all these sections and go
> to [#Installation](#installation)

This script takes a concept from network security called [ARP Spoofing](https://en.wikipedia.org/wiki/ARP_spoofing).
[ARP](https://en.wikipedia.org/wiki/Address_Resolution_Protocol) is a network
protocol that has a single goal: To make machines find themselves within a LAN.
It's a **link layer (Layer 2)** protocol translation tool that is able to transform Internet
protocols (layer 3) such as IPV4 into Network Addresses (MAC Addresses). The only way to
do this is by asking the network who is the owner of some IP.

ARP works by broadcasting 28-byte-long packages that can either be a **Request**
or a **Reply**. When a computer wants to send something to another computer in
the network, it will broadcast an **ARP Request** asking _"Who has IP X, tell
Y"_ and the computer that owns said IP will broadcast an **ARP Reply** directed
to that sender saying _"IP X is at MAC address Z"_.

Once this reply is received, the receiving party will cache the response and now
knows that, if they need to send a package to IP, they can use Z as the MAC
routing address for the link layer.

### The vulnerability

ARP is a trust-based protocol. There's no way one computer can know if the
responder or the requester is who they claim to be, this is what the entire
protocol is all about. So they will trust whatever message is sent in the
network. This opens space for malicious actors to spam the network with ARP
packets saying _"Hey IP X is at MAC Y"_, and the receiving targets will
**always** believe that package and update their routing tables locally.

![](https://upload.wikimedia.org/wikipedia/commons/thumb/3/33/ARP_Spoofing.svg/2880px-ARP_Spoofing.svg.png)

The image above shows a _duplex ARP spoofing_, which transmits the target's
packages to you, but also tells the gateway that you are the target, which
transmits the responses to those packages back to you. This is used for
main-in-the-middle attacks and it's **not** what we are doing here.

> You can check the routing table of any Unix-based computer either with `arp-a`
> which basically does `cat /proc/net/arp` or `ip neigh` which is newer.

So nothing blocks a malicious actor from sending an ARP package every second to
one or multiple targets saying that they're someone else. This is called **ARP
Spoofing**. In general, it's an entry point vulnerability, which can be used to
get access to something, but the attacker needs to either have access to a
physical machine in the LAN, or they need to be a node in the LAN themselves, so
it's a pretty complicated attack to pull off by itself.

**BUT, you can hack yourself! :smile:**

### The process

This is a simple bash script that relies on the `dsniff` package and the
`arpspoof` binary to spam the network with ARP packages targeting a list of IPV4
addresses every second stating that this machine is now the _default gateway_
(a.k.a your router).

When this happens, all the target machines think the default route to anything
in the Internet is through that machine, that just captures the packages and
drop them all. **Which renders the target machines offline**.

This is what happens when you run the `netkill.sh 192.168.123.123` command.
Suppose you're on the attacking machine with IP `192.168.123.102` and the
default gateway is `192.168.123.1`:

1. We ping the host to check if it's online and discoverable
   - We do this because the attacker machine **must** have the target's MAC
     address stored in its own ARP table. Go to [#Caveats](#caveats) to see why
2. If the host is online, we start `arpspoof` which sends an **ARP REPLY** telling `192.168.123.123` that
   `192.168.123.1` is at `01:12:23:45:56:78`, which happens to be
   `192.168.123.102`'s MAC address
3. `192.168.50.123` picks that up and updates the local ARP table with
   _"192.168.123.1 is at 01:12:23:45:56:78"_
4. This ARP Reply is re-sent at every second and the process is put in
   background
5. The spoofed target's IP is saved in `/tmp/netkill_targets` and the running
   PID of the process is also saved in `/tmp/netkill_pids`
   - Logs are kept in `/var/log/netkill/yyyy-mm-dd/<ip>` for 7 days you can
     `tail -f` those live to see ARP activity
6. Once the `netkill --stop` command is sent, we loop through all the PIDs in
   the saved PID file and kill all the processes, this will send some ARP
   packages back with the correct MAC address of the gateway again
7. To restore the ARP tables to the original state, we loop through all the IPs
   in the `/tmp/netkill_targets` file and issue `ping` requests (30
   of them) for the target machine, this helps to stimulate the machine to send
   a broadcast ARP to ask for the new addresses of the attack machine
   - This is not necessarily true, it works most of the time, but it can take
     some seconds or minutes for the network to recover

That's it. Local network nuking.

## Installation

> This will ONLY work in linux-based systems but can nuke whatever machine in
> the LAN

1. Install `dsniff` in your preferred distro (e.g in Arch it's `pacman -S dsniff`)
2. Copy the script somewhere in your `$PATH`
3. Run `chmod +x` in the file to allow you to run it
4. Run it as root (needed because of the `arpspoof` command)

## Usage

You can run this command in two ways:

- Listing IPs manually: `netkill <ip1> <ip2> <ip3> ...`
- Using an IP list file: `netkill ./myfile` where the file contains one IP per
  line (the file doesn't have to contain any specific extension)

```toml
# comments need to be on a line
192.168.123.100
# This comment is also valid
192.168.123.101
192.150.123.124 # this comment is invalid and will break
```

If you want to test it before executing, put `-d` **BEFORE** the file name or IP
list to enter dry run mode: `netkill -d <ip> <ip>`

Or just run `netkill` to see the usage.

Remember to set the `DEFAULT_GATEWAY` and `DEFAULT_INTERFACE` variables before running

```sh
DEFAULT_INTERFACE=eth0
DEFAULT_GATEWAY="192.168.123.1"
```

You can get the local network link using `ip link` and getting the name of your
local interface, usually it's something like `wl0`, `eth0`, or `enp1s0`

The default gateway can also be obtained from the `ip route` command which will
give you something like this:

```sh
$ ip route
default via 192.168.123.1 dev eth0 proto dhcp src 192.168.123.124 metric 100
192.168.123.0/24 dev eth0 proto kernel scope link src 192.168.123.124 metric 100
```

The default gateway is the one that ends with `.1`, usually it's also the same
address you use to access your router's web interface.

```sh
export DEFAULT_GATEWAY=192.168.50.1
export DEFAULT_INTERFACE=enp1s0
netkill.sh <ip>
```

### Environment variables

- `DEFAULT_GATEWAY`: Sets the default gateway
- `DEFAULT_INTERFACE`: Sets the default interface
- `DRY_RUN`: Starts the dry run mode

## Caveats

- There's something called _gratuitous ARP_. This happens when either the
  destination MAC is `ff:ff:ff:ff:ff:ff` or sometimes when the destination IP is
  `0.0.0.0`. This can instruct some devices in the network that it's a broadcasted
  message, which means **ALL THE DEVICES WILL PICK IT UP** and they will all
  update their ARP tables, rendering all the network useless until the ARP cache
  expires (usually it takes 30~60 mins), how do I know that? _Experience_...
- In general, routers are pretty dumb things. Except for those who are not. Most
  routers will have their ARP tables, IP tables, and all the other cached stuff
  cleaned upon a power cycle, so turning it off and on again _really_ solves
  things. If you end up the case above and have a common, consumer grade, router
  (like ASUS or whatever) turning it off and on again will solve your issue.
  However, for **mesh** routers like TP-Link Decos, for example, this will not
  work. And I have a theory for why.
  - Since mesh routers need to remember all the MAC and IP addresses of
    previously connected devices because they need to roam them around when you
    change device, their ARP tables are actually kept between
    resets. So power cycling will not do anything.
  - In this case, the only way to solve the previous issue is either by
    changing your own MAC address and connecting as a new device in the network,
    or waiting around 60 to 90 minutes to the ARP cache to expire. Again, ask me
    how I know it...
- You can forge ARP replies in case you mess up using tools like `nemesis` and
  `bettercap` but in general is something that you won't
