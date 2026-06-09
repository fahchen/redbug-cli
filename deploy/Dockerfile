# Demo target node image. OTP must match the controller's OTP major (28) so the
# redbug beam the controller injects runs cleanly on the target.
FROM erlang:28-alpine

COPY target-entrypoint.sh /usr/local/bin/target-entrypoint.sh
RUN chmod +x /usr/local/bin/target-entrypoint.sh

# epmd + fixed distribution port
EXPOSE 4369 9100

ENTRYPOINT ["/usr/local/bin/target-entrypoint.sh"]
