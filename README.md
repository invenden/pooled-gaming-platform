# Pooled Gaming Platform
A configurable, repeatable game for TRC20 tokens.

## Getting started
The development environment uses Tronbox and the Trontools/quickstart docker image.

```
npm install -g tronbox
docker pull trontools/quickstart
```

Start the docker image.  To configure correctly, it must be started from scratch, it cannot restart.
```
docker run -it \
  -p 9090:9090 \
  --rm \
  --name tron \
  trontools/quickstart
```
