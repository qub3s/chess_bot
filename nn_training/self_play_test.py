import chess
import chess.pgn
import numpy as np
import random
import torch
import torch.nn as nn
from torch.utils.data import Dataset, DataLoader
from sklearn.model_selection import train_test_split
import sys
from cairosvg import svg2png
import cv2
import threading

class result_prediction(nn.Module):
    def __init__(self):
        super().__init__()
    
        self.both = nn.Sequential(
            nn.Linear(12 * 64 + 1, 64),
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
        #print("Epoch: ",epoch)
        sys.stdout.flush()

        train_loss = train( train_dataloader, optimizer, model, loss_function, device )
        
        val_loss = validate( val_dataloader, model, loss_function, device )

        #print("Train loss: ", train_loss)
        #print("Valitation loss: ", val_loss)
        
        early_stopping(val_loss, model)

        if early_stopping.early_stop:
            print("Early Stopp !!!")
            break
        
        train_losses.append(train_loss)
        val_losses.append(val_loss)
        
    return train_losses, val_losses, train_accs, val_accs

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

def isover(board):
    if board.is_insufficient_material() or board.is_checkmate() or board.is_stalemate() or board.is_fifty_moves() or board.is_fivefold_repetition():
        return True
    else: 
        return False

def winner(board):
    s = board.outcome()
    if s != None:
        s = s.result()
    else:
        return 0
    
    sd = "1/2-1/2"
    sl = "0-1"
    sw = "1-0"

    if s == sd:
        return 0
    elif s== sl:
        return -1
    elif s== sw: 
        return 1
    
def calc_move(model, board, whitetomove, device, lvl):
    if board.is_insufficient_material() or board.is_stalemate() or board.is_fifty_moves() or board.is_fivefold_repetition():
        return 0
    
    if board.is_checkmate():
        return winner(board)*float('inf')
    
    if lvl == 0:
        return 0
    
    lm = [ str(x) for x in board.legal_moves ]

    moves = []
    for x in lm:
        bo = board.copy()
        bo.push_san(x)
        moves.append(calc_move(model, bo, whitetomove == False, device, lvl-1))
    
    if whitetomove:
        # black
        idx = moves.index(min(moves))
    else:
        # white
        idx = moves.index(max(moves))
    
    return idx

def play_game(model, device, board, lvl, ret):
    whitetomove = True
    r_moves = []

    while not isover(board):        
        lm = [ str(x) for x in board.legal_moves ]
        
        if random.randint(0,5) == 1:
            lm = [ str(x) for x in board.legal_moves ]

            moves = []
            for x in lm:
                bo = board.copy()
                bo.push_san(x)
                moves.append(calc_move(model, bo, whitetomove == False, device, lvl))
            
            if whitetomove:
                # black
                idx = moves.index(min(moves))
            else:
                # white
                idx = moves.index(max(moves))
            board.push_san(lm[idx])
        else:
            board.push_san( lm[random.randint(0,len(lm)-1)] )
            r_moves.append( to_numpy(board) )
        
        whitetomove = whitetomove == False


    if winner(board) != None and winner(board) != 0:
        w = winner(board)
        for x in r_moves:
            ret.append((w, x))    
    
seed = 22
torch.manual_seed(seed)
random.seed(seed)
np.random.seed(seed)

device = "cpu"
model_path = "self_play.pth"

# create model
model = result_prediction()
#model.load_state_dict(torch.load(model_path, weights_only=True, map_location=torch.device(device)))
model.to(device)

import datetime

now = datetime.datetime.now()
print(now)
for x in range(0,100000):
    random.seed(x)
    inp = np.random.rand(769)
    inp = torch.tensor(inp).float()
    model(inp)

now = datetime.datetime.now()
print(now)

epochs = 10
lr = 0.001
batch_size = 1000

loss_function = torch.nn.MSELoss()
epochs = 10
cnt = 0

X = []
y = []


while True:
    board1 = chess.Board()
    board2 = chess.Board()

    train_moves1 = []
    train_moves2 = []

    t1 = threading.Thread(target=play_game, args=(model, device, board1, 1, train_moves1))
    t2 = threading.Thread(target=play_game, args=(model, device, board2, 1, train_moves2))

    t1.start()
    t2.start()

    t1.join()
    t2.join()
    
    if winner(board1) != 0 and train_moves1 != []:
        for x in train_moves1:
            a, b = to_binary(x[1], True, 0)
            y.append(x[0])
            X.append(b)
    
    if winner(board2) != 0 and train_moves2 != []:
        for x in train_moves2:
            a, b = to_binary(x[1], True, 0)
            y.append(x[0])
            X.append(b)
    
    if len(y) > batch_size:
        cnt += 1
        print(cnt)
        early_stopping = EarlyStopping(model_path, patience=10, verbose=False, delta=0)
        optimizer = torch.optim.Adam(model.parameters(), lr=lr)


        X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.1, random_state=42)

        train_loader = simple_dataset(X_train, y_train)
        test_loader = simple_dataset(X_test, y_test)

        run_training(model, optimizer, loss_function, device, epochs, train_loader, test_loader, early_stopping )
        model.load_state_dict(torch.load(model_path, weights_only=True, map_location=torch.device(device)))
        
        y = []
        X = []

        out = cv2.VideoWriter("videos/"+str(cnt)+'.mp4', cv2.VideoWriter_fourcc(*'mp4v') , 15, (390,390))

        board = chess.Board()
        whitetomove = True
        counter = 0
        # make video
        while not isover(board):
            lm = [ str(x) for x in board.legal_moves ]
            moves = []
            if len(lm) == 0:
                break

            for x in lm:
                bo = board.copy()
                bo.push_san(x)
                b = to_numpy(bo)

                a, stm = to_binary(b, whitetomove, 0)
                stm = torch.tensor(stm).to(device).float()

                moves.append(model(stm).item())

            whitetomove = whitetomove == False    
            r_move = False

            if random.randint(0,10) < 8:
                if whitetomove:
                    idx = moves.index(min(moves))
                else:
                    idx = moves.index(max(moves))
                board.push_san(lm[idx])
            else:    
                board.push_san(lm[random.randint(0,len(lm)-1)])
                r_move = True
            
            boardsvg = chess.svg.board(board=board)
            svg2png(bytestring=boardsvg, write_to='temp.jpg')
            png = cv2.imread('temp.jpg') 

            if r_move:
                image = np.zeros((300, 300, 3), np.uint8)
                image[:] = (0, 0, 255)
                out.write(image)
                out.write(image)

            for x in range(5):
                out.write(png)

            counter += 1
            if counter == 1000:
                break
        out.release()

    