# Deploying to remote host from local host

This guides explains how to efficiently host the application on a remote host,
without using docker-compose.

(You can replace `docker` with `podman`.)
Depending on your environment, you may need to run the commands as root
(with `sudo`).

Create and start docker registry:

(`~/.local/share/` is the $XDG_DATA_HOME.
Use `/usr/share/` if running as root.)

```sh
mkdir ~/.local/share/docker-registry

docker run --name docker-registry \
    -p 5000:5000 \
    -v ~/.local/share/docker-registry:/var/lib/registry \
    docker.io/library/registry:latest
```
```sh
docker start docker-registry
```

Build the Bluesky Labeler app image:
```sh
docker build --tag bsky-labeler .
```

Push image to local registry:
```sh
docker tag bsky-labeler localhost:5000/bsky-labeler

docker push localhost:5000/bsky-labeler
```

Open an ssh connection with a reverse-tunnel:
```sh
ssh -R localhost:5000:localhost:5000 <remote>
```

On the remote host, pull the image:
```sh
docker pull localhost:5000/bsky-labeler
```

Stop and remove the existing container, if any:
```sh
docker stop bsky-labeler
docker rm bsky-labeler
```

Create a docker network:
```sh
sudo docker network create bsky-labeler-network
```

First ensure the dependencies. Refer to the __Running Dependencies__ header.

Create a `bsky_labeler_secret`. You can look at the `secret.example` file
in this repository as a template.
If using `podman`, alternatively, you can use `podman secrets` to create a
secret and skip the mounting `/run/secrets/`.

Create a `patterns.txt` file.

Run the container:
```sh
docker run -d --name bsky-labeler \
    -e MIN_LIKES=10 \
    -e REGEX_FILE="/pattern/patterns.txt" \
    -e POSTGRES_HOST=bsky-labeler-postgres \
    -e LABELER_LABEL=<yourlabelid>
    -v <path-to-patterns.txt>:/pattern/patterns.txt \
    -v <path-to-bsky_labeler_secret>:/run/secrets/bsky_labeler_secret \
    --network bsky-labeler-network \
    localhost:5000/bsky-labeler
```

You can add port publish option `-p 127.0.0.1:4000:4000` if you want to access
the admin dashboard.


Logs can be viewed with
```sh
docker logs bsky-labeler --follow
```

You can open a remote Elixir shell within the container:
```sh
docker exec -it bsky-labeler /app/bin/bsky_labeler remote
```

## Updating

Ensure `docker-registry` is started.

Build, tag, and push the image:
```sh
docker build --tag bsky-labeler .
docker tag bsky-labeler localhost:5000/bsky-labeler
docker push localhost:5000/bsky-labeler
```

Ensure reverse tunnel:
```sh
ssh -R localhost:5000:localhost:5000 $REMOTE_HOST
```

On the remote:
```sh
docker stop bsky-labeler
docker rm bsky-labeler
docker pull localhost:5000/bsky-labeler
```
Then call the run command again.

## Running dependencies

### Postgres

Start a __Postgres__ container:
```sh
docker run -d --name bsky-labeler-postgres \
  -e POSTGRES_PASSWORD=<your-postgres-password> \
  -e POSTGRES_DB=bsky_labeler_repo \
  -v bsky-labeler-postgres-data:/var/lib/postgresql/data \
  --network bsky-labeler-network \
  docker.io/library/postgres \
  --synchronous_commit=off
```

The data will be stored in the named volume `bsky-labeler-postgres-data`.

You may use the Postgres CLI argument `--synchronous_commit=off` to improve IO
performance, as the data written to disk is not critical.

### Prometheus (optional)

```sh
docker run -d --name prometheus \
  -p 127.0.0.1:9090:9090 \
  -v <config-dir-for-prometheus>:/etc/prometheus \
  -v prometheus-data:/prometheus \
  --network bsky-labeler-network \
  prom/prometheus
```

To monitor system metrics as well, you can start a __Prometheus Node Exporter__:
```sh
docker run -d --name node-exporter \
  --pid="host" \
  -v "/:/host:ro,rslave" \
  --network bsky-labeler-network \
  quay.io/prometheus/node-exporter:latest \
  --path.rootfs=/host
```

Example prometheus.yml:
```yml
scrape_configs:
  - job_name: bsky_labeler
    scrape_interval: 15s
    static_configs:
      - targets:
        - bsky-labeler:4000
    basic_auth:
      username: admin
      password: prom_password

  - job_name: node_exporter
    scrape_interval: 15s
    static_configs:
      - targets:
        - node-exporter:9100
```

You can access the Prometheus dashboard or run Grafana locally
by tunneling with ssh:
```sh
ssh -L localhost:9090:localhost:9090 <remote>
```
