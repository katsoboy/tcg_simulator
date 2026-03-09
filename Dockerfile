# Build stage: Elixir + Node for assets and release
ARG ELIXIR_VERSION=1.15.7
ARG OTP_VERSION=26.2.2
ARG DEBIAN_VERSION=bookworm-20240312

ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}-slim"

FROM ${BUILDER_IMAGE} AS builder

# Install Node.js (for Tailwind and esbuild)
RUN apt-get update -y && apt-get install -y build-essential git nodejs npm curl unzip \
    && apt-get clean && rm -f /var/lib/apt/lists/*_*

# Install hex + rebar
RUN mix local.hex --force && \
    mix local.rebar --force

WORKDIR /app

# Set env for production
ENV MIX_ENV="prod"

# Copy mix files
COPY mix.exs mix.lock ./

# Install dependencies
RUN mix deps.get --only $MIX_ENV
RUN mkdir config

# Copy config (needed for compile)
COPY config/config.exs config/${MIX_ENV}.exs config/

# Compile deps (no full compile yet - we need lib and priv)
RUN mix deps.compile

# Copy lib, priv, rel
COPY lib lib
COPY priv priv
COPY rel rel

# Copy assets
COPY assets assets

# Compile application and build release
RUN mix compile
RUN mix assets.deploy
RUN mix release

# Runtime stage
FROM ${RUNNER_IMAGE}

RUN apt-get update -y && \
    apt-get install -y libssl3 libncurses6 locales ca-certificates \
    && apt-get clean && rm -f /var/lib/apt/lists/*_* \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG en_US.UTF-8
ENV LANGUAGE en_US:en
ENV LC_ALL en_US.UTF-8

WORKDIR /app

# Set env
ENV MIX_ENV="prod"

# Copy release from builder
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/tcg_simulator ./

# Fly.io: IPv6 and Erlang distribution
ENV ECTO_IPV6=true
ENV ERL_AFLAGS="-proto_dist inet6_tcp"

USER nobody

# Release runs on PORT from Fly (default 8080)
ENV PHX_SERVER=true

RUN chmod +x /app/bin/migrate /app/bin/server

CMD ["/app/bin/server"]
