//Round_Server_Center

// BEGUN:         July 18, 2015
// LAST UPDATED:  May 15, 2016
// VERSION:       8
// UPDATES:       
//    7 = Flexible field size, drawn boundaries, name changing, AI enemies
//    8 = Tags shortened to reduce lag [x], Server split to reduce lag [ ], Round locations and velocities [x], Improve shooting protocols [x], Promote teaming [ ], Improve enemies [x], Change scoring dynamics and upgrades [ ], Worsen spider package (dagger,speed) [ ], Termite combat package [ ]

/*  
    File Format Example
      name[player0]score[0]
      name[player1]score[1]
      
    clientList Format Example
      name[N]score[S]location[X,Y]angle[T]package[P]health[H]alpha[A]zombie[Z]_code(C)address[#]
      
    objectList Format Example                                                          REMEMBER: clients take away walls, healthBoxes, ammoBoxes, coins, and bullets, as well as change their own healths and scores independently
      name[field]radius[W/2]                                                                     I send radius so as not to create a new info tag
      name[wall]location[X,Y]radius[R]                                                           walls are circles; collision is simple between circles
      name[healthBox]location[X,Y]                                                               returns 50 health                                               
      name[ammoBox]location[X,Y]                                                                 completely refills ammo
      name[coin]location[X,Y]                                                                    always worth 1
      name[bullet]location[X,Y]velocity[Xv,Yv]target[Xf,Yf]damage[D]owner[player0]               target helps show if bullet has gone too far
      name[detonator]location[X,Y]radius[R]alpha[A]damage[D]owner[player1]                       alpha corresponds to time till detonation
      name[smokescreen]location[X,Y]radius[R]alpha[A]                                            alpha corresponds to transparency
      name[hazardRing]location[X,Y]radius[R]alpha[A]damage[D]owner[player2]                      alpha corresponds to current radius, radius corresponds to final radius
      name[grenade]location[X,Y]velocity[Xv,Yv]target[Xf,Yf]radius[R]damage[D]owner[player3]     target helps show if grenade has gone too far (like the bullet, but creates hazardRing)
      name[demolition]location[X,Y]velocity[Xv,Yv]target[Xf,Yf]radius[R]damage[D]owner[player3]  same as grenade, but shrinks/removes walls on contact
      name[fanshot]location[X,Y]velocity[Xv,Yv]radius[R]alpha[A]damage[D]owner[player4]          alpha corresponds to additional bullets to the original with a deviation angle of 0 ON EACH SIDE (decided not to use it...)
      name[laserPoint]location[X,Y]alpha[A]                                                      alpha corresponds to whether the sight should be deleted
    
    enemyList Format Example
      location[X,Y]angle[T]package[P]
      
    iconList Format Example
      location[X,Y]alpha[A]shape[x,y;x,y;x,y;x,y]$location[X,Y]alpha[A]shape[x,y;x,y;x,y;x,y]
      location[X,Y]alpha[A]shape[x,y;x,y;x,y;x,y]$location[X,Y]alpha[A]ellipse[w,h]$location[X,Y]alpha[A]shape[x,y;x,y;x,y;x,y]
*/

import processing.net.*;

Server server;
int serverPort = 44445;

String[] fileEntries;                                   //Replica of the data file. (each entry is a new line)
StringList filedList;                                   //Saved clients
StringList clientList;                                  //Signed clients
StringList objectList;                                  //List of objects
ArrayList<Enemy> enemyList = new ArrayList<Enemy>();    //List of enemies, they are objects because they have many individual functions.

int iconNumber = 10;                          //Number of special icons
String[] codeList = new String[iconNumber];   //List of acceptable icon codes
String[] iconList = new String[iconNumber];   //List of icon drawing instructions

String clientHD = "C:";          //Data headings
String objectHD = "O:";
String messageHD = "M:";
String newHD = "N:";
String loadHD = "L:";
String spawnHD = "S:";
String deleteHD = "D:";

String addressID = "@[";        //Shared client data tags (some used in object/enemy data)
String nameID = "n[";              
String scoreID = "s[";
String angleID = "<[";
String locationID = "l[";
String packageID = "p[";
String alphaID = "a[";

String healthID = "h[";          //Private client data tags
String zombieID = "z[";

String velocityID = "v[";      //Object-specific tags
String radiusID = "r[";
String targetID = "t[";
String damageID = "d[";
String ownerID = "o[";

String receiverID = ">[";         //The intended receiving client of the following data (for server -> client broadcast) tag
String codeCD = "_(";             //Special icon code tag

String chatID = "c[";              //Tag for chat-line strings.
StringList chatList;               //Chat-Line

char endID = ']';
char endCD = ')';
char endHD = '*';

char splitID = '$';                   //used only when necessary: separation of client DELETE objects; separation of SPAWN objects; separation of shapes in icon drawing instructions.

int fieldMinimum = 1000;
int fieldMaximum = 3160;
int fieldWidth = fieldMaximum;        //Dimensions of the battlefield (field is a square, so width & height) (how far a client can go)
int playerMaximum = 10;
int coinTimer = 0;                    //Timer for placing coins randomly throughout the battlefield
int enemyTimer = 0;                   //"               " enemies "                               ".

int clientScope = 750;                //Variables for managing how much information if sent to the clients
float[] viewLimits = new float[4];    // [0] = minX  [1] = maxX  [2] = minY  [3] = maxY

PFont displayFont;
PFont chatFont;

String chatBoxString = "[,],*,:,$,TAB = Not Permitted. Limit = 60 char.";  //Initial string for textBoxChat();

void setup() {
  size(600,600);
  server = new Server(this,serverPort);
  
  fileEntries = loadStrings("owen_Round_Server_Center.txt");
  filedList = new StringList();
  clientList = new StringList();
  objectList = new StringList();
  chatList = new StringList();
  
  for(int i=0; i<fileEntries.length; i++) {
    filedList.append(fileEntries[i]);
  }
  
  createIcons();
  createEnvironment();                  //Can fieldWidth be changed w/o changing the client-side? —— NO
  
  displayFont = createFont("Chalkboard", 12, true);
  chatFont = createFont("Monospaced", 10, true);
  
  println("Server Device IP:  " + Server.ip());
}

void draw() {  
  printData();                                //Display filed clients, signed clients, and/or objects lists.
  
  textBoxChat(25,height-25);                  //Enable server to send chats to all players.
  
  displayChatLine();                          //Show chat history.
  
  respond();                                  //Read and respond to client messages (can be for newHD, loadHD, clientHD, spawnHD, deleteHD, and messageHD.)
  
  checkZombies();                             //Function for dealing with zombie clients (who quit w/o using the ESCAPE button).
  
  updateEnvironment();                        //Update environment outside of direct client initiation. (moving bullets and grenades, creating explosions, etc.)
  
  spawnItems();                               //Create healthBoxes, ammoBoxes, coins, walls, and enemies depending upon #items, #clients, #score, and #coinTimer.
  
  updateEnemies();                            //Run enemy functions for every enemy in the enemyList
  
  adjustLimits();                             //Adjust limits of view for clients and stretch fieldWidth
  
  broadcastClientList();                      //Send all client data
  
  broadcastObjectList();                      //Send visible environment data (items and enemies)
}