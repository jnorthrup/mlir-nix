#include "Composite/MinMaxHeap.h"
#include "Composite/Series.h"
#include "mlir/ExecutionEngine/CRunnerUtils.h"

extern "C" MLIR_CRUNNERUTILS_EXPORT bool _mlir_ciface_trikeshed_cluster_order(
    StridedMemRefType<int64_t, 1> *keys, StridedMemRefType<int64_t, 1> *order) {
  int64_t n = keys->sizes[0];
  if (n < 0 || n > 23 || order->sizes[0] != n ||
      keys->strides[0] != 1 || order->strides[0] != 1)
    return false;
  auto input = uint32_t(n) |composite::j| [keys](uint32_t i) { return keys->data[keys->offset + i]; };
  uint32_t at = 0;
  return composite::clusterOrder(input, [&](uint32_t row) { order->data[order->offset + at++] = row; });
}
