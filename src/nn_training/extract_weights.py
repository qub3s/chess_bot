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
            nn.Linear(12 * 64 + 1, 64),
            nn.ReLU(),
            nn.Linear(64, 32),
            nn.ReLU(),
            nn.Linear(32, 1),
        )

    def forward(self, x1):
        x = torch.flatten( x1)
        return self.both(x)

def write_to_csv(model, filename):
    f = open(filename, "w")
    line = "" 

    for x in model.layer:
        if "Linear" in str(x):
            line += str(x.in_features)
        
        if "ReLU" in str(x):
            line += "ReLU"
        
        line += ","
    
    f.write(line+"\n")
    
    
    line = ""
    for layer in model.layer:
        f.write("\n")
        if "Linear" in str(layer):
            for i in range(layer.weight.shape[0]):
                for j in range(layer.weight.shape[1]):
                    line += str(round(layer.weight[i][j].item(), 4))+","
                f.write(line+"\n")
        line = ""

        
    f.close()

model = result_prediction()
write_to_csv(model, "model_files/model.csv")

