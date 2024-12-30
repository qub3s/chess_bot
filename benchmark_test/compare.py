import torch
import numpy as np
import csv
import random

# this file compares the performance of the self implemented nn to pytorches performance

with open('src/mnist_test.csv') as file:
    content = file.read()

lines = content.split("\n")[1:]

y = []
X = []

for l in lines:
    if l != "":
        s = l.split(",")
        y.append(int(s[0]))

        x = []
        for i in range(1,len(s)):
            x.append(int(s[i]))

        X.append(x)
        

class Model(torch.nn.Module):
    def __init__(self):
        super(Model, self).__init__()

        self.linear1 = torch.nn.Linear(784, 10000)
        self.activation = torch.nn.ReLU()
        self.linear2 = torch.nn.Linear(10000, 1)

    def forward(self, x):
        x = self.linear1(x)
        x = self.activation(x)
        x = self.linear2(x)
        return x

model = Model()

lr = 0.01
epochs = 300
batch_size = 100 

loss_function = torch.nn.MSELoss()
optimizer = torch.optim.Adam(model.parameters(), lr=lr)

for a in range(epochs):
    Xs = []
    ys = []

    for b in range(batch_size):
        i = random.randint(0,100)
        Xs.append(X[i])
        ys.append(y[i])

    Xs = torch.tensor(Xs).float()
    ys = torch.tensor(ys).float()

    res = model(Xs)
    loss = loss_function(res, ys)
    loss.backward()

    print(loss.item())

    optimizer.step()






