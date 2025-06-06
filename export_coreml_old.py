import coremltools as ct
import torch

# Reload trained model
model = CNNOracle()
model.load_state_dict(torch.load("cnn_oracle.pth"))
model.eval()

# Trace and convert
example_input = torch.rand(1, 1, 40)
traced = torch.jit.trace(model, example_input)
mlmodel = ct.convert(traced, inputs=[ct.TensorType(name="input", shape=example_input.shape)])

mlmodel.save("CNNOracle.mlmodel")
