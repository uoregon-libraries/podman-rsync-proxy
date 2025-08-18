FROM alpine:3

RUN apk add --no-cache rsync

# Make sure the container waits for rsyncing, but also eventually exits in case
# the script doesn't manage to take it down properly. We give a huge window
# (ten hours) to allow for slow network xfers.
CMD ["sleep", "36000"]
