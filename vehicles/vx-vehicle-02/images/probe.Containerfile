# A zone or compute payload: reflects probes, and carries a shell and wget for the flow checks.
FROM scratch
COPY vxprobe /vxprobe
COPY busybox /bin/busybox
ENTRYPOINT ["/vxprobe", "reflect"]
