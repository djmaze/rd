# rd (remote docker)

rd is a tool which allows switching your local Docker client between remote Docker hosts.

## Prerequisites

* You need to have a remote Docker host [configured with TLS](https://docs.docker.com/engine/security/https/) and SSH access.
* The client certificate bundle (`ca.pem`, `key.pem` and `cert.pem`) needs to be present in the `~/.docker` directory of your SSH user on the remote host. 

For RancherOS hosts, just add the option `-r` (`--setup-ros`) to the `add` command. See below.

## Install

Just copy the `rd` script to a directory somewhere in your `PATH`.

## Quickstart

```bash
rd add --setup-ros rancher@dockerhost1
eval $(rd env dockerhost1)
# Now operating on remote docker
docker info

eval $(rd env local)
# Now operating on local docker again
docker info
```

## Detailed usage

### Add hosts

```bash
rd add ubuntu@dockerhost1 ubuntu@dockerhost2 ...
rd add --setup-ros rancher@dockerhost1 rancher@dockerhost2 ...
rd add --setup-ros --swarm my-swarm rancher@swarmnode1 rancher@swarmnode2
```

`rd add` will fetch the TLS certificates from the remote hosts and save them locally for use.

Use the `-s` or `--swarm` flag in order to mark the host(s) as belonging to the named swarm.

With the `-r` or `--setup-ros` option and a RancherOS host, TLS will be automatically configured [according to the RancherOS documentation](http://rancher.com/docs/os/v1.1/en/configuration/setting-up-docker-tls).

### Setup the docker env

```bash
# Setup the env for dockerhost1
eval (rd env dockerhost1)
# Setup the env for any host from my-swarm
eval (rd env --swarm my-swarm)
# Reset env to localhost
eval (rd env local)
```

`rd env` will output the env variables needed for remote access to the chosen host.

When using `--swarm`, a random host from the given swarm will be used.

### Remove hosts

```bash
rd remove dockerhost1
```

`rd remove` will remove the configuration and certificates for the given host.

### List hosts

```bash
rd list
```

`rd list` lists the names of all known hosts.
