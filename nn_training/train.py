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
    
        self.both = nn.Sequential(
            nn.Linear(12 * 64 + 1, 256),
            nn.ReLU(),
            nn.Linear(256, 64),
            nn.ReLU(),
            nn.Linear(64, 32),
            nn.ReLU(),
            nn.Linear(32, 1),
        )

    def forward(self, x1):
        x = torch.flatten( x1)
        return self.both(x)

class EarlyStopping:
    def __init__(self, checkpoint_path, patience=5, verbose=False, delta=0):
        self.patience = patience
        self.verbose = verbose
        self.counter = 0
        self.best_score = None
        self.early_stop = False
        self.val_loss_min = np.inf
        self.delta = delta
        self.model_checkpoint_path = checkpoint_path

    def __call__(self, val_loss, model):

        score = -val_loss

        if self.best_score is None:
            self.best_score = score
            self.save_checkpoint(val_loss, model)
        elif score < self.best_score + self.delta:
            self.counter += 1
            if self.counter >= self.patience:
                self.early_stop = True
        else:
            self.best_score = score
            self.save_checkpoint(val_loss, model)
            self.counter = 0
    
    def save_checkpoint(self, val_loss, model):
        if self.verbose:
            print(f'Validation Loss Decreased ({self.val_loss_min:.6f} --> {val_loss:.6f}).  Saving model ...')
        torch.save(model.state_dict(), self.model_checkpoint_path)
        self.val_loss_min = val_loss

class simple_dataset(Dataset):
    def __init__(self, X, y):
        self.X = torch.Tensor(X.copy())
        self.y = torch.Tensor(y.copy())

    def __len__(self):
        return len(self.y)

    def __getitem__(self, idx):
        return self.X[idx], self.y[idx]

def accuracy(y, pred):  
    pred_max = torch.argmax(pred, dim=1)
    y_max = torch.argmax(y, dim=1)
    
    return (sum(y_max==pred_max)/len(y_max)).cpu()

def train(dataloader, optimizer, model, loss_fn, device):   
    model.train()
    losses = []
    acc = []
    # Loop over each batch of data provided by the dataloader
    for X, y in dataloader:
        X = X.to(device)
        Y = y.to(device)
        
        pred = model(X)
        
        loss = loss_fn(pred, Y)
        losses.append(loss.item())
        
        optimizer.zero_grad()
        
        loss.backward()
        optimizer.step()
    
    return sum(losses) / len(losses)

def validate(dataloader, model, loss_fn, device):
    model.train()
    losses = []
    acc = []
    # Loop over each batch of data provided by the dataloader
    for X, y in dataloader:
        X = X.to(device)
        Y = y.to(device)
        
        with torch.no_grad():
            pred = model(X)
        
            loss = loss_fn(pred, Y)
            losses.append(loss.item())

    
    return sum(losses) / len(losses)

def run_training(model, optimizer, loss_function, device, num_epochs, train_dataloader, val_dataloader, early_stopping):
    train_losses = []
    val_losses = []
    train_accs = []
    val_accs = []
    
    for epoch in range(num_epochs):
        print("Epoch: ",epoch)
        sys.stdout.flush()

        train_loss = train( train_dataloader, optimizer, model, loss_function, device )
        
        val_loss = validate( val_dataloader, model, loss_function, device )

        print("Train loss: ", train_loss)
        print("Valitation loss: ", val_loss)
        
        early_stopping(val_loss, model)

        if early_stopping.early_stop:
            print("Early Stopp !!!")
            break
        
        train_losses.append(train_loss)
        val_losses.append(val_loss)
        
    return train_losses, val_losses, train_accs, val_accs

def to_numpy(board):
    b = np.zeros((64)) 
    s = str(board)

    i = 0
    
    for x in s:
        
        if x == "K":
            b[i] = 1
        if x == "Q":
            b[i] = 2
        if x == "R":
            b[i] = 3
        if x == "B":
            b[i] = 4
        if x == "N":
            b[i] = 5
        if x == "P":
            b[i] = 6

        if x == "k":
            b[i] = 7
        if x == "q":
            b[i] = 8
        if x == "r":
            b[i] = 9
        if x == "b":
            b[i] = 10
        if x == "n":
            b[i] = 11
        if x == "p":
            b[i] = 12

        if x != "\n" and x != " ":    
            i = i + 1
    return b

def to_binary(bo, white, res):
    side_to_move = np.zeros(( 769 ))

    a = [1,2,3,4,5,6]
    b = [7,8,9,10,11,12]

    for x in range(0, len(a)):
        for y in range(64):
            side_to_move[x*64+y] = bo[y] == a[x]

    for x in range(0, len(b)):
        for y in range(64):
            side_to_move[(x+6)*64+y] = bo[y] == a[x]

    side_to_move[768] = white
    return res, side_to_move

def nth(i, x): 
    for a,b in enumerate(x):
        if a == i:
            return b

def count(i):
    return sum(1 for e in i)

def make_x_random_moves(n,board):
    b = board.copy()

    for x in range(n):
        lm = b.legal_moves
        c = lm.count()
        if c == 0:
            break
        r = random.randint(0,c)
        move = nth(r, lm) 
        move = chess.Move.from_uci(str(move)) 
        b.push(move)
    
    return b


# https://www.chessprogramming.org/Stockfish_NNUE
# train the first network on the results of games -> train another network base on the predictions of this network
# extract 2 boards, one 3 moves before the end and one 8 moves before the end

last_x_moves = 1
pgn = open("datasets/lichess_db_standard_rated_2015-05.pgn", encoding="utf-8")

sd = "1/2-1/2"
sl = "0-1"
sw = "1-0"

positions = []
Y = []
elements = 100000000
cnt = 0

while True:
    game = chess.pgn.read_game(pgn)

    if game == None:
        break
        
    board = game.board()
    if len(Y) == elements:
        break	
    
    #cnt += 1
    #print(cnt)

    if "WhiteElo" in game.headers.keys() and "BlackElo" in game.headers.keys() and int(game.headers["WhiteElo"]) >= 1700 and int(game.headers["BlackElo"]) >= 1700 and ("Classical" in game.headers["Event"] or "Blitz" in game.headers["Event"]):
        total_move_num = count(game.mainline_moves())

        whitetomove = True
        for i, move in enumerate(game.mainline_moves()):
            board.push(move)
            
            whitetomove = whitetomove == False
            
            if i >= total_move_num-last_x_moves and i > 20:
                b = to_numpy(board)
                result = None
                if game.headers["Result"] == sd:
                    result = 0
                if game.headers["Result"] == sl:
                    result = -1
                if game.headers["Result"] == sw:
                    result = 1
                
                y, stm = to_binary(b, whitetomove, result)
                Y.append(y)
                positions.append(stm)


values, counts = np.unique(np.array(Y), return_counts=True)

counts = counts - min(counts)
for i, c in enumerate(counts):
    if c != 0:
        l = len(Y)
        x = 0
        while c > 0:
            if Y[x] == values[i]:
                Y.pop(x)
                positions.pop(x) 
                l = l-1
                c = c-1
                x -= 1
            
            x += 1

            if c == 0 or x == l:
                break

print(len(Y))
values, counts = np.unique(np.array(Y), return_counts=True)

np.save("results.npy", np.array(Y))
np.save("positions.npy", np.array(positions))

Y = np.load('results.npy')
positions = np.load('positions.npy')
values, counts = np.unique(Y, return_counts=True)
print(values)
print(counts)

print(len(Y))

device = "cuda:0"

model_path = "model.pth"
epochs = 100
lr = 0.0001
batch_size = 1000

early_stopping = EarlyStopping(model_path, patience=10, verbose=False, delta=0)

model = result_prediction()
model.to(device)

loss_function = torch.nn.MSELoss()
optimizer = torch.optim.Adam(model.parameters(), lr=lr)

X_train, X_test, y_train, y_test = train_test_split(positions, Y, test_size=0.1, random_state=42)

train_loader = simple_dataset(X_train, y_train)
test_loader = simple_dataset(X_test, y_test)

run_training(model, optimizer, loss_function, device, epochs, train_loader, test_loader, early_stopping )