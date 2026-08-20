FROM alpine:latest

RUN apk add --no-cache prosody openssl

COPY prosody.cfg.lua /etc/prosody/prosody.cfg.lua
COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh \
	&& mkdir -p /var/lib/prosody /var/run/prosody /etc/prosody/certs \
	&& chown -R prosody:prosody /var/lib/prosody /var/run/prosody /etc/prosody

USER prosody

EXPOSE 5222

ENTRYPOINT ["/entrypoint.sh"]
