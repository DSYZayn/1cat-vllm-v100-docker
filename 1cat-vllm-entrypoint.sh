#!/bin/sh

# Run a user-supplied preparation hook before starting the inference server.
# The hook is intentionally a shell command so it can install a temporary
# dependency or run a mounted Python patch without rebuilding the image.
set -eu

if [ "${VLLM_PRESTART_HOOK_RAN:-0}" != "1" ] && [ -n "${VLLM_PRESTART_HOOK:-}" ]; then
    export VLLM_PRESTART_HOOK_RAN=1
    echo "Running VLLM_PRESTART_HOOK"
    if [ -f "${VLLM_PRESTART_HOOK}" ]; then
        /bin/sh "${VLLM_PRESTART_HOOK}"
    else
        /bin/sh -c "${VLLM_PRESTART_HOOK}"
    fi
    unset VLLM_PRESTART_HOOK VLLM_PRESTART_HOOK_RAN
fi

launch_api_server() {
    exec python3 -m vllm.entrypoints.openai.api_server "$@"
}

launch_vllm_serve() {
    exec /usr/local/1cat-vllm/bin/vllm-real serve "$@"
}

case "${VLLM_LAUNCH_MODE:-auto}" in
    api-server)
        launch_api_server "$@"
        ;;
    serve)
        launch_vllm_serve "$@"
        ;;
    auto)
        if [ "$#" -eq 0 ]; then
            launch_api_server
        fi

        case "$1" in
            vllm)
                shift
                exec /usr/local/1cat-vllm/bin/vllm-real "$@"
                ;;
            serve)
                exec /usr/local/1cat-vllm/bin/vllm-real "$@"
                ;;
            --*)
                launch_api_server "$@"
                ;;
            *)
                # GPUStack supplies the model path as the first argument when
                # this image is configured as the vLLM serve entrypoint.
                launch_vllm_serve "$@"
                ;;
        esac
        ;;
    *)
        echo "Unsupported VLLM_LAUNCH_MODE: ${VLLM_LAUNCH_MODE}" >&2
        exit 64
        ;;
esac
