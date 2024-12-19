import chess
import chess.pgn
import numpy as np
import random
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from sklearn.model_selection import train_test_split
import sys

class result_prediction(nn.Module):
    def __init__(self):
        super().__init__()
    
        self.layer = nn.Sequential(
            nn.Linear(20, 10),
            nn.ReLU(),
            nn.Linear(10, 5),
            nn.ReLU(),
            nn.Linear(5, 1),
        )

    def forward(self, x1):
        x = torch.flatten( x1)
        return self.both(x)

def write_to_csv(model, filename, precision):
    f = open(filename, "w")
    line = "" 
    
    for x in model.layer:
        if "Linear" in str(x):
            line += str(x.in_features) + "," + str(x.out_features) + "\n"
            f.write(line)
            line = ""

            for i in range(x.out_features):
                for j in range(x.in_features):
                    line += str(round(x.weight[i][j].item(), precision))+","
            f.write(line+"\n")
            line = ""

            for i in range(x.out_features):
                line += str(round(x.bias[i].item(), precision))+","
            f.write(line+"\n")
            line = ""

    f.write(line+"\n")
    f.close()

model = result_prediction()
write_to_csv(model, "model_files/model.csv", 8)

