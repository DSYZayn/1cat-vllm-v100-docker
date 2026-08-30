#!/bin/sh

# Some runtimes override the image entrypoint with `vllm serve`. Keep the hook
# in this CLI wrapper as well, so that entrypoint overrides do not bypass the
# image's pre-start contract.
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

exec /usr/local/1cat-vllm/bin/vllm-real "$@"
