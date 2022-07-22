FROM rust:1.58-buster as build-env

ARG FEATURES
ARG RS_VERSION

RUN mkdir /data

WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive LANG=C.UTF-8 TZ=UTC TERM=xterm-256color
ENV WEB_VAULT_ENABLED=false

RUN apt-get update && \
    apt-get install -y pkg-config libsqlite3-dev libmariadb-dev-compat libmariadb-dev libpq-dev

RUN git clone https://github.com/dani-garcia/vaultwarden.git /app && \
    cd /app && \
    git checkout ${RS_VERSION} && \
    cargo build --features ${FEATURES} --release

RUN mkdir /libsneeded/ && \
    for i in $(ldd /app/target/release/vaultwarden | awk '{print $3}' |grep lib); do cp $i /libsneeded/ ; done

FROM node:16-buster as web-build

ARG VAULT_VERSION
ARG RS_WEB_VERSION

USER root

RUN git clone https://github.com/bitwarden/clients.git /vault && \
    cd /vault/ && \
#     git checkout ${VAULT_VERSION} && \
    git checkout v2.28.1 && \
    git submodule update --recursive --init

RUN git clone https://github.com/dani-garcia/bw_web_builds.git /rspatch && \
    cd /rspatch && \
    git checkout ${RS_WEB_VERSION} && \
    mv /rspatch/patches /patches && \
    mv /rspatch/scripts/apply_patches.sh /apply_patches.sh && \
    chown -R node:node /patches /apply_patches.sh /vault /rspatch

USER node

WORKDIR /vault

RUN bash /apply_patches.sh && find . -type f -exec sed -i 's/#175DDC/#00683C/g' {} \;

RUN git config --global url."https://github.com/".insteadOf ssh://git@github.com/ && \
    npm ci --legacy-peer-deps && \
    npm audit fix --legacy-peer-deps || true && \
    cd apps/web && npm run dist:oss:selfhost && \
    find build -name "*.map" -delete && \
    echo "{\"version\":\"${RS_WEB_VERSION}\"}" > build/bwrs-version.json

RUN mv build web-vault

FROM gcr.io/distroless/cc-debian11:latest

ENV ENV production
ENV NODE_ENV production
ENV ROCKET_ENV "production"
ENV ROCKET_PORT=80
ENV ROCKET_WORKERS=10
ENV ROCKET_LIMITS={json=10485760}
ENV WEB_VAULT_ENABLED=true

COPY --from=build-env /data /data
COPY --from=web-build /vault/web-vault ./web-vault
COPY --from=build-env /app/target/release/vaultwarden /
COPY --from=build-env /libsneeded/* /usr/lib/

EXPOSE 80
EXPOSE 3012

VOLUME /data

CMD ["./vaultwarden"]
