import torch
import numpy as np
import csv
import random
import time

# this file compares the performance of the self implemented nn to pytorches performance
class Model(torch.nn.Module):
    def __init__(self):
        super(Model, self).__init__()

        self.activation = torch.nn.ReLU()
        self.linear1 = torch.nn.Linear(768, 50)
        self.linear2 = torch.nn.Linear(50, 32)
        self.linear3 = torch.nn.Linear(32, 1)

    def forward(self, x):
        x = self.linear1(x)
        x = self.activation(x)
        x = self.linear2(x)
        x = self.activation(x)
        x = self.linear3(x)

        return x

def forewad_bechmark(epochs):
    model = Model()

    loss_function = torch.nn.MSELoss()
    optimizer = torch.optim.Adam(model.parameters(), lr=0.01)

    for a in range(epochs):
        Xs = np.zeros((1,768))

        Xs = torch.tensor(Xs).float()
        res = model(Xs)

torch.set_num_interop_threads(16) 
torch.set_num_threads(16)  
print(torch.get_num_threads())
print(torch.get_num_interop_threads())

start = time.time()
a = torch.randn(20000, 20000)
b = torch.randn(20000, 20000)
c = torch.matmul(a, b)

#forewad_bechmark(100000)
end = time.time()
print(end - start)






