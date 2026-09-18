"""Minimal CPU-only training loop on synthetic data.

Vehicle for exercising the platform (container, k8s, Argo), not a real
ML workload — a tiny MLP fit to a synthetic linear-regression target.
"""

import time

import numpy as np
import torch
from torch import nn

NUM_SAMPLES = 2048
NUM_FEATURES = 20
BATCH_SIZE = 64
EPOCHS = 20
LEARNING_RATE = 1e-3


def make_synthetic_data(
    num_samples: int, num_features: int, seed: int = 0
) -> tuple[torch.Tensor, torch.Tensor]:
    rng = np.random.default_rng(seed)
    x = rng.standard_normal((num_samples, num_features)).astype(np.float32)
    true_weights = rng.standard_normal(num_features).astype(np.float32)
    noise = rng.standard_normal(num_samples).astype(np.float32) * 0.1
    y = x @ true_weights + noise
    return torch.from_numpy(x), torch.from_numpy(y).unsqueeze(1)


def build_model(num_features: int) -> nn.Module:
    return nn.Sequential(
        nn.Linear(num_features, 64),
        nn.ReLU(),
        nn.Linear(64, 32),
        nn.ReLU(),
        nn.Linear(32, 1),
    )


def main() -> None:
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    device_name = torch.cuda.get_device_name(0) if device.type == "cuda" else "cpu"
    print(f"device={device} device_name={device_name!r}", flush=True)

    x, y = make_synthetic_data(NUM_SAMPLES, NUM_FEATURES)
    x, y = x.to(device), y.to(device)

    model = build_model(NUM_FEATURES).to(device)
    optimizer = torch.optim.Adam(model.parameters(), lr=LEARNING_RATE)
    loss_fn = nn.MSELoss()

    start = time.monotonic()
    for epoch in range(1, EPOCHS + 1):
        permutation = torch.randperm(NUM_SAMPLES)
        epoch_loss = 0.0
        for i in range(0, NUM_SAMPLES, BATCH_SIZE):
            batch_idx = permutation[i : i + BATCH_SIZE]
            batch_x, batch_y = x[batch_idx], y[batch_idx]

            optimizer.zero_grad()
            pred = model(batch_x)
            loss = loss_fn(pred, batch_y)
            loss.backward()
            optimizer.step()
            epoch_loss += loss.item() * len(batch_idx)

        epoch_loss /= NUM_SAMPLES
        print(f"epoch={epoch} loss={epoch_loss:.4f}", flush=True)

    elapsed = time.monotonic() - start
    print(f"training complete elapsed_s={elapsed:.2f}", flush=True)


if __name__ == "__main__":
    main()
