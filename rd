#!/bin/bash
set -euo pipefail
[ -n "${DEBUG:-}" ] && set -x

CONFIG_DIR=~/.config/rd
SWARM_CONFIG_DIR="${CONFIG_DIR}/swarms"
NODES_CONFIG_DIR="${CONFIG_DIR}/nodes"
HOSTNAME_REGEXP='^\([[:alnum:]-]*\).'

make_swarm_config_dir() {
  mkdir -p "$SWARM_CONFIG_DIR"
}

node_config_dir() {
  local node="$1"
  echo "$NODES_CONFIG_DIR/$(hostname_for_node "$node")"
}

remove_node_config_dir() {
  local node="$1"
  rm "$(node_config_dir "$node")" -fR
}

make_node_config_dir() {
  local node="$1"
  remove_node_config_dir "$node"
  mkdir -p "$(node_config_dir "$node")"
}

nodes() {
  ls -1 "$NODES_CONFIG_DIR"
}

swarm_config_file() {
  local swarm="$1"
  echo "$SWARM_CONFIG_DIR/$swarm"
}

swarms_for_node() {
  local node="$1"
  grep --extended-regexp --recursive --files-with-matches ".*@$node" "$SWARM_CONFIG_DIR"
}

add_to_swarm() {
  local swarm="$1" node="$2"

  make_swarm_config_dir
  echo "$node" >> "$(swarm_config_file "$swarm")"
}

remove_node_from_swarms() {
  local node="$1"

  for swarm_config in $(swarms_for_node "$node"); do
    echo Removing node from swarm \""$(basename "$swarm_config")"\"
    sed -i "/.*@$node/d" "$swarm_config"
  done
}

files_for_node() {
  local node="$1"
  local docker_dir=".docker"
  echo "$node":"${docker_dir}/ca.pem" "$node":"${docker_dir}/key.pem" "$node":"${docker_dir}/cert.pem"
}

add_node() {
  local swarm="$1" node="$2"

  make_node_config_dir "$node"
  scp $(files_for_node "$node") "$(node_config_dir "$node")"
}

remove_node() {
  local node="$1"

  remove_node_from_swarms "$node"
  remove_node_config_dir "$node"
}

hostname_for_node() {
  local node="$1"
  echo "${node#*@}"
}

get_random_node_for_swarm() {
  local swarm="$1"

  sort -R "$(swarm_config_file "$swarm")" | head -n1
}

check_node_exists() {
  local node="$1"

  if [ -e "$(node_config_dir "$node")" ]; then
    return 0
  else
    return 1
  fi
}

check_swarm_exists() {
  local swarm="$1"

  if [ -e "$(swarm_config_file "$swarm")" ]; then
    return 0
  else
    return 1
  fi
}

output_docker_env_for_node() {
  echo Using node \""$(hostname_for_node "$node")"\" >&2
  cat <<-EOF
		export DOCKER_TLS_VERIFY="1"
		export DOCKER_HOST="tcp://$(hostname_for_node "$node"):2376"
		export DOCKER_CERT_PATH="$(node_config_dir "$node")"
	EOF
}

reset_docker_env() {
  echo Resetting env to localhost >&2
  cat <<-EOF
		export DOCKER_TLS_VERIFY=
		export DOCKER_HOST=
		export DOCKER_CERT_PATH=
	EOF
}

setup_ros_node() {
  local node="$1"
  local full_hostname host_part
  local host_part

  full_hostname="$(hostname_for_node "$node")"
  host_part="$(expr "$full_hostname" : "$HOSTNAME_REGEXP")"

  echo Setting up TLS on rancher host "$full_hostname"

  ssh -T "$node" << CMD
    set -euo pipefail

    sudo ros config set rancher.docker.tls true
    sudo ros tls gen --server -H localhost -H "$full_hostname" -H "$host_part"
    sudo system-docker restart docker
    sudo ros tls gen
CMD
}

add() {
  local swarm="$1"
  shift
  local setup_ros="$1"
  shift
  local nodes=("$@")

  for node in "${nodes[@]}"; do
    if [[ "$setup_ros" == "1" ]]; then
      setup_ros_node "$node"
    fi

    if [ -n "$swarm" ]; then
      echo Adding node "$node" to "$swarm"
    else
      echo Adding node "$node"
    fi

    add_node "$swarm" "$node"
    [ -n "$swarm" ] && add_to_swarm "$swarm" "$node"
  done
}

remove() {
  local nodes=("$@")

  for node in "${nodes[@]}"; do
    if check_node_exists "$node"; then
      echo Removing node "$node"
      remove_node "$node"
    else
      echo Error, node \""${node}"\" unknown! >&2
      exit 1
    fi
  done
}

env() {
  local swarm="$1"
  local node="${2:-}"

  if [ -n "$swarm" ]; then
    # Use any swarm node
    if check_swarm_exists "$swarm"; then
      node="$(get_random_node_for_swarm "$swarm")"
      output_docker_env_for_node "$node"
    else
      echo Error, swarm "\"${swarm}"\" unknown! >&2
      exit 1
    fi
  elif [[ "$node" =~ ^(local|localhost)$ ]]; then
    reset_docker_env
  else
    if check_node_exists "$node"; then
      output_docker_env_for_node "$node"
    else
      echo Error, node \""${node}"\" unknown! >&2
      exit 1
    fi
  fi
}

list() {
  nodes
}

main() {
  local opts swarm="" setup_ros="0"

  opts=$(getopt -o s: --long swarm: -o r --long setup-ros -o h --long help -- "$@")
  eval set -- "$opts"

  while true; do
    case "$1" in
      -r|--setup-ros) setup_ros=1; shift 1;;
      -s|--swarm) swarm="$2"; shift 2;;
      --) shift; break;;
      *) break;
    esac
  done

  [ -n "${DEBUG:-}" ] && [ -n "${swarm}" ] && echo Using swarm "$swarm"

  command="${1:-}"
  [ -n "$command" ] && shift
  case "$command" in
    add)
      add "$swarm" "$setup_ros" "$@";;
    env)
      env "$swarm" "$@";;
    rm|remove)
      remove "$@";;
    ls|list)
      list "$@";;
    -h|--help)
      printf "Available commands:\n\n"
      printf "add [-s|--swarm <swarm>] [-r|--setup-ros] <host> [<host> ..]\n"
      printf "\tAdd one or more hosts\n\n"
      printf "env [-s|--swarm <swarm>] [<host>]\n"
      printf "\tGet the environment for a host or any host in a swarm\n\n"
      printf "rm <host>\n"
      printf "\tRemove a host\n\n"
      printf "ls\n"
      printf "\tList known hosts\n"
      ;;
    *)
      echo "Syntax: rd <COMMAND> [<ARGS..>]"
      echo Use --help for more information.
      exit 1
  esac
}

main "$@"
