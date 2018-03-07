#!/bin/bash
# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

#
# Script     : kickstart.sh 
# Usage      : ./kickstart.sh
# Author     : Sujen Shah, Giuseppe Totaro
# Date       : 05-25-2017 [MM-DD-YYYY]
# Last Edited: 02-21-2017, Omid Davtalab
# Description: This script automatically builds the docker containers, pulls 
#              the firefox engine and then performs the docker compose tool for 
#              defining and running the multi-container application that allow 
#              Sparkler Crawl Environment to be used by a Subject Matter Expert.
# Notes      : This script is included in the following repository:
#              https://github.com/sujen1412/sce
#

function print_usage() {
	echo "Usage: $0 [-up | -stop | -start | -down] [-l /path/to/log]"
	printf "\n\t-down\n\t\tStops containers and removes containers, networks, volumes, and images created by docker-compose up.\n"
	printf "\n\t-stop\n\t\tStops running containers without removing them. They can be started again with docker-compose start.\n"
	printf "\n\t-start\n\t\tStarts existing containers for a service.\n"
	printf "\n\t-up\n\t\tBuilds, (re)creates, starts, and attaches to containers for a service (default command).\n"
	printf "\n\t-l <dir>, --log-file <dir>\n\t\tPath to the log file. If it is not specified, the script writes out everything on the standard output.\n"
}

# NOTE: Currently, this function is not necessary.
function find_port() {
	local port_number=$1
	while [ $(lsof -i :$port_number | wc -l) -ne 0 ]
	do
		port_number=$((port_number+1))
	done

	echo $port_number
}

# NOTE: Currently, this function is not necessary as we are using a static 
# configuration file.
# Create a new docker-compose.yml file based on the available ports. We do not 
# use environment variables because the script can be executed from other 
# terminals whereas the variables would be set only for the current shell and 
# all processes started from the current shell.
function docker_compose_conf() {
	echo "version: '2'"
	echo "networks:"
	echo "  sparkler_net:"
	echo "    driver: bridge"
	echo "    driver_opts:"
	echo "      com.docker.network.enable_ipv6: \"false\""
	echo "    ipam:"
	echo "      driver: default"
	echo "      config:"
	echo "      - subnet: 172.200.0.0/24"
	echo "        gateway: 172.200.0.1"
	echo ""
	echo "services:"
	echo "    firefox:"
	echo "      image: \"selenium/standalone-firefox-debug\""
	echo "      ports:"
	echo "        - \"$FIREFOX_PORT:4444\""
	echo "        - \"$VNC_PORT:5900\""
	echo "      networks:"
	echo "        sparkler_net:"
	echo "          ipv4_address: 172.200.0.2"
	echo "    sparkler:"
	echo "      image: \"sujenshah/sce-sparkler\""
	echo "      ports:"
	echo "        - \"$SOLR_PORT:8983\""
	echo "      volumes:"
	echo "        - ../data/solr/crawldb/data:/data/solr/server/solr/crawldb/data"
	echo "        - ../data/crawl-segments:/data/crawl-segments"
	echo "        - ../data/dumper/dump:/data/sparkler/dump"
	echo "      networks:"
	echo "        sparkler_net:"
	echo "          ipv4_address: 172.200.0.3"
	echo "    domain-discovery:"
	echo "      image: \"sujenshah/sce-domain-explorer\""
	echo "      ports:"
	echo "        - \"$DD_PORT:5000\""
	echo "      volumes:"
	echo "        - ../data/dumper:/projects/sce/data/dumper"
	echo "      networks:"
	echo "        sparkler_net:"
	echo "          ipv4_address: 172.200.0.4"
}

function compose_up() {
	mkdir -p $DIR/data/solr/crawldb/data
	mkdir -p $DIR/data/crawl-segments
	mkdir -p $DIR/data/dumper/dump
	
	cd $DIR/$SPARKLER
	
	docker pull davtalab/sce-nb 2>&1 | tee -a $LOG_FILE 
	
	cd $DIR/$DD
	
	docker pull sujenshah/sce-domain-explorer 2>&1 | tee -a $LOG_FILE
	
	docker pull $FIREFOX  2>&1 | tee -a $LOG_FILE
	
	cd $DIR
	cd $COMPOSE
	
	# Test if default ports are available
	#SOLR_PORT=$(find_port $SOLR_PORT)
	#echo "SOLR_PORT=$SOLR_PORT" 2>&1 | tee -a $LOG_FILE
	#DD_PORT=$(find_port $DD_PORT)
	#echo "DD_PORT=$DD_PORT" 2>&1 | tee -a $LOG_FILE
	#FIREFOX_PORT=$(find_port $FIREFOX_PORT)
	#echo "FIREFOX_PORT=$FIREFOX_PORT" 2>&1 | tee -a $LOG_FILE
	#VNC_PORT=$(find_port $VNC_PORT)
	#echo "VNC_PORT=$VNC_PORT" 2>&1 | tee -a $LOG_FILE

	#docker_compose_conf > docker-compose.yml

	# Running docker-compose up -d starts the containers in the background and leaves them running
	docker-compose up -d 2>&1 | tee -a $LOG_FILE
	
	local sparkler_id=$(docker ps -q -f "name=compose_sparkler_1")
	local dd_id=$(docker ps -q -f "name=compose_domain-discovery_1")
	local firefox_id=$(docker ps -q -f "name=compose_firefox_1")
	
	[[ -z $sparkler_id ]] && echo "An error occurred while starting the sparkler container!" || echo "The sparkler container is started with id ${sparkler_id}"
	[[ -z $dd_id ]] && echo "An error occurred while starting the domain-discovery container!" || echo "The domain-discovery container is started with id ${dd_id}"
	[[ -z $firefox_id ]] && echo "An error occurred while starting the firefox container!" || echo "The firefox container is started with id ${firefox_id}"

	
	if [ ! -z $sparkler_id ] && [ ! -z $dd_id ] && [ ! -z $firefox_id ]
	then
		echo "All the Docker containers for Sparkler CE are properly running!" | tee -a $LOG_FILE
		echo "The Solr instance is available on http://0.0.0.0:${SOLR_PORT}" | tee -a $LOG_FILE
		echo "The DD explorer is available on http://0.0.0.0:${DD_PORT}/explorer" | tee -a $LOG_FILE
	fi
}

function compose_down() {
	cd $DIR/$COMPOSE
	docker-compose down 2>&1 | tee -a $LOG_FILE
}

function compose_stop() {
	cd $DIR/$COMPOSE
	echo "Stopping running containers without removing them. They can be started again with docker-compose start." | tee -a $LOG_FILE
	docker-compose stop 2>&1 | tee -a $LOG_FILE
}

function compose_start() {
	cd $DIR/$COMPOSE
	echo "Starting existing containers for a service." | tee -a $LOG_FILE
	docker-compose start 2>&1 | tee -a $LOG_FILE
}

while [ ! -z $1 ]
do
	case $1 in
		-up|-stop|-start|-down)
			[[ ! -z $CMD ]] && { echo "Error: you can run only one action among up, stop, start, and down!"; print_usage; exit 1; } 
			CMD="${1:1}"
			;;
		-l|--log-file)
			LOG_FILE="$2"
			shift
			;;
			*)
			print_usage
			exit 1
			;;
		esac
	shift
done

[[ -z $CMD ]] && CMD="up"
SPARKLER="sparkler-docker"
DD="domain-discovery"
COMPOSE="compose"
FIREFOX="selenium/standalone-firefox-debug"

# Default port numbers
SOLR_PORT=8983
DD_PORT=5000
FIREFOX_PORT=4444
VNC_PORT=9559

## Full directory name of the script no matter where it is being called from
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

if [ -z $LOG_FILE ]
then 
	mkdir -p $DIR/logs
	LOG_FILE="$DIR/logs/kickstart.log"
	[[ -f $LOG_FILE ]] && cat "$LOG_FILE" >> "$LOG_FILE.$(date +%Y%m%d)"
fi

echo "The requested operation has been started. All the log messages will be reported also to $LOG_FILE"

eval "compose_${CMD}"
