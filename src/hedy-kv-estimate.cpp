// Hedy patch: exact KV-cache size estimate for a not-yet-created context.
//
// Hedy's capacity gates must know how much memory llama_init_from_model will
// allocate for KV *before* creating the context. The public API exposes no
// per-layer geometry, and formula-based estimates in the app charged every
// layer full-context KV — a ~7x overestimate for sliding-window models
// (Gemma 4 12B @16k ctx: ~7 GiB estimated vs 736 MiB real) that refused
// generations which fit comfortably.
//
// This mirrors the sizing actually performed by llama_kv_cache /
// llama_kv_cache_iswa with Hedy's context params (type_k/v = f16, kv_unified
// default, n_seq_max = 1, swa_full = false — see llama_bindings.cpp).
// If the sizing logic in llama-kv-cache-iswa.cpp changes, update this file in
// the same hedy-vendor patch.

#include "llama-model.h"

#include <algorithm>
#include <cstdint>

extern "C" uint64_t hedy_llama_model_kv_bytes_impl(
        const struct llama_model * model,
        int32_t n_ctx,
        int32_t n_batch);

extern "C" uint64_t hedy_llama_model_kv_bytes_impl(
        const struct llama_model * model,
        int32_t n_ctx,
        int32_t n_batch) {
    if (!model || n_ctx <= 0) {
        return 0;
    }
    const llama_hparams & hparams = model->hparams;

    // Matches cparams.n_ubatch = min(n_batch, default 512) in llama_context.
    const uint32_t n_ubatch =
        std::min<uint32_t>(n_batch > 0 ? (uint32_t) n_batch : 512u, 512u);

    // SWA cache cell count: pad(min(n_ctx, n_swa + n_ubatch), 256) — the
    // swa_full=false branch of llama_kv_cache_iswa.
    const bool has_swa = hparams.swa_type != LLAMA_SWA_TYPE_NONE &&
                         hparams.n_swa > 0;
    uint32_t swa_cells = 0;
    if (has_swa) {
        const uint32_t raw =
            std::min<uint32_t>((uint32_t) n_ctx, hparams.n_swa + n_ubatch);
        swa_cells = ((raw + 255u) / 256u) * 256u;
    }

    // f16 K and V entries: 2 bytes per element.
    const uint64_t bytes_per_element = 2;

    uint64_t total = 0;
    for (uint32_t il = 0; il < hparams.n_layer(); ++il) {
        if (!hparams.has_kv(il)) {
            continue;   // shared-KV layers allocate nothing (Gemma 4)
        }
        if (hparams.is_recr(il)) {
            continue;   // recurrent layers use the (small) rs cache instead
        }
        const uint64_t cell_bytes = bytes_per_element *
            (hparams.n_embd_k_gqa(il) + hparams.n_embd_v_gqa(il));
        const uint64_t cells =
            (has_swa && hparams.is_swa(il)) ? swa_cells : (uint32_t) n_ctx;
        total += cell_bytes * cells;
    }
    return total;
}
