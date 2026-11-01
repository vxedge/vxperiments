# The OTA server. vxedged passes its arguments, so the entrypoint is the binary alone.
FROM scratch
COPY vxota /vxota
ENTRYPOINT ["/vxota"]
