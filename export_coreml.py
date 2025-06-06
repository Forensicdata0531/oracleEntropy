import coremltools as ct
import torch
from cnn_oracle_model import CNNOracle

INPUT_LENGTH = 48  # Match input dimension from training

# 1. Load the PyTorch model
model = CNNOracle(input_length=INPUT_LENGTH)
model.load_state_dict(torch.load("cnn_oracle.pth"))
model.eval()

# 2. Create example input tensor for tracing
example_input = torch.rand(1, 1, INPUT_LENGTH)

# 3. Trace the model
traced_model = torch.jit.trace(model, example_input)

# 4. Convert to CoreML
mlmodel = ct.convert(
    traced_model,
    source="pytorch",
    inputs=[ct.TensorType(shape=example_input.shape)],
)

# 5. Save the model
mlmodel.save("CNNOracle.mlpackage")
print("✅ Exported CNNOracle.mlpackage")
