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
        self.linear1 = torch.nn.Linear(768, 1000)
        self.linear2 = torch.nn.Linear(1000, 32)
        self.linear3 = torch.nn.Linear(32, 1)

    def forward(self, x):
        x = self.linear1(x)
        x = self.activation(x)
        x = self.linear2(x)
        x = self.activation(x)
        x = self.linear3(x)

        return x

def forewad_bechmark(runs):
    model = Model()

    optimizer = torch.optim.Adam(model.parameters(), lr=0.01)

    Xs = np.zeros((1,768))
    Xs = torch.tensor(Xs).float()

    for a in range(runs):
        res = model(Xs)

torch.set_num_interop_threads(1) 
torch.set_num_threads(1)  

start = time.time()
forewad_bechmark(100000)
end = time.time()
print(end - start)






