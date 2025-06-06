# cnn_oracle_train.py
import torch
import torch.nn as nn
import json
import numpy as np
from cnn_oracle_model import CNNOracle

def hex_to_float_vector(midstate_hex, tail_hex):
    raw_bytes = bytes.fromhex(midstate_hex + tail_hex)
    return np.frombuffer(raw_bytes, dtype=np.uint8).astype(np.float32) / 255.0

def main():
    with open("oracle/top_midstates.json") as f:
        data = json.load(f)

    X, y = [], []
    for entry in data:
        vec = hex_to_float_vector(entry["midstate"], entry["tail"])
        X.append(vec)
        y.append(entry["score"])

    X = np.stack(X)
    y = np.array(y).astype(np.float32)

    print("X shape:", X.shape)

    X_tensor = torch.tensor(X).unsqueeze(1)
    y_tensor = torch.tensor(y).unsqueeze(1)

    model = CNNOracle(input_length=X.shape[2])
    optimizer = torch.optim.Adam(model.parameters(), lr=1e-3)
    loss_fn = nn.MSELoss()

    for epoch in range(50):
        pred = model(X_tensor)
        loss = loss_fn(pred, y_tensor)
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
        print(f"Epoch {epoch+1}, Loss: {loss.item():.6f}")

    torch.save(model.state_dict(), "cnn_oracle.pth")

if __name__ == "__main__":
    main()
