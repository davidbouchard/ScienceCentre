import ddf.minim.*;
import ddf.minim.analysis.*;
import ddf.minim.effects.*;
import ddf.minim.signals.*;
import ddf.minim.spi.*;
import ddf.minim.ugens.*;
import java.util.*;
import java.io.*;
import netP5.*;
import oscP5.*;
import deadpixel.keystone.*;

import com.jogamp.opengl.*;

// GLOBAL PARAMETERS

int TIMEOUT = 5;  // in seconds, this controls the amount of time the creature will stay on the screen 
float SPIN_SPEED_MAX = 0.005;

OscP5 osc;
int listeningPort = 9000;

Model prevModel;
Model model;
MaskAnimator mAnim = new MaskAnimator();

Timer timer = new Timer(1000); 

Model arrow;

String lastCode = "";
String[] areaNames = {"sci", "hum", "liv", "inn", "spa"};

enum State {
  FADE_IN_PREVIOUS, FADE_IN_WAIT, FADE_IN_CURRENT, FADE_OUT, 
    SPIN, IDLE
} 

// The current area
String area;

State state = State.IDLE;

float spinAngle = 0;
float spinSpeed = SPIN_SPEED_MAX;

float fadeOut;

// Keystone
int widthLonger = 800;
int widthShorter = 800;

PGraphics left;
PGraphics middle;
PGraphics right;

Keystone ks1;
CornerPinSurface surface1;
CornerPinSurface surface2;
CornerPinSurface surface3;

Sounds sounds;
PFont bitFont; 

PJOGL pgl;
GL2ES2 gl;

boolean showAlreadyVisited = false;
boolean showFoundEverything = false;

//===================================================
void settings() {
  // Load properties 
  try {
    Properties configFile = new Properties();
    String dp = dataPath("config.properties");
    FileInputStream f = new FileInputStream(dp);
    configFile.load(f);
    println(configFile);
    area = configFile.getProperty("AREA");
    int fs = Integer.parseInt(configFile.getProperty("FULLSCREEN"));
    if (fs == 1) {
      fullScreen(P3D);
    } else {
      int w =  Integer.parseInt(configFile.getProperty("WIN_W"));
      int h =  Integer.parseInt(configFile.getProperty("WIN_H"));      
      size(w, h, P3D);
    }
  }
  catch(Exception e) {
    e.printStackTrace();
  }
}


void setup() {  
  // required on the PI or textures won't work
  hint(DISABLE_TEXTURE_MIPMAPS);
  noCursor();

  pgl = (PJOGL)beginPGL();
  gl = pgl.gl.getGL2ES2();
  gl.glEnable(gl.GL_CULL_FACE);
  endPGL();

  // PI simulator
  //frameRate(10);

  osc = new OscP5(this, listeningPort);
  osc.plug(this, "scan", "/scan"); 

  middle = createGraphics(width, height, P3D); 

  prevModel = new Model();
  model = new Model();

  arrow = new Model();
  PImage arrowImage = loadImage("arrow.png");
  arrow.setImage(arrowImage, null, arrowImage, null); 

  ks1 = new Keystone(this);
  surface1 = ks1.createCornerPinSurface(widthLonger, widthShorter, 20);
  left = createGraphics(widthLonger, widthShorter, P3D);
  surface2 = ks1.createCornerPinSurface(widthShorter, widthLonger, 20);
  middle = createGraphics(widthShorter, widthLonger, P3D);
  surface3 = ks1.createCornerPinSurface(widthLonger, widthShorter, 20);
  right = createGraphics(widthLonger, widthShorter, P3D);

  ks1.load();
  ap = surface2; // for calibration 

  bitFont = createFont("PressStart2P.ttf", 24);
  textFont(bitFont);
  left.textFont(bitFont);
  middle.textFont(bitFont);
  right.textFont(bitFont);

  state = State.IDLE;

  sounds = new Sounds(this, area);
}

//===================================================
void draw() {
  // Left
  left.beginDraw();  
  left.background(0, 0);
  left.translate(left.width/2, left.height/2);
  left.rotateZ(radians(270));
  left.rotateY(spinAngle);
  renderScene(left);
  left.endDraw();

  // right
  right.beginDraw();  
  right.background(0, 0);
  right.translate(right.width/2, right.height/2);
  right.rotateZ(radians(90));
  right.rotateY(spinAngle);
  renderScene(right);
  right.endDraw();

  // middle 
  middle.beginDraw();  
  middle.background(0, 0);
  middle.pushMatrix();
  middle.translate(middle.width/2, middle.height/2);
  middle.rotateY(radians(90));
  middle.rotateY(spinAngle);
  renderScene(middle);
  middle.popMatrix();
  renderOverlay(middle);
  middle.endDraw();

  // draw using the surface objects
  background(0);
  surface1.render(left);
  surface2.render(middle);
  surface3.render(right);

  if (ks1.isCalibrating()) {
    textSize(12);
    text("Lock sides: " + lockSides, 30, 30);
    text("Move by: " + moveBy, 30, 60);
  }
}

//===================================================
// Use for text / this will not rotate and only appear in the middle panel 

float textY = 50;

void renderOverlay(PGraphics g) {  
  g.noLights();
  g.textFont(bitFont);
  g.textAlign(CENTER);
  g.fill(255); 
  g.textSize(24);
  if (showAlreadyVisited) {
    g.text("Already visited!\nTry looking for\nanother terminal!", g.width/2, textY);
  }

  if (showFoundEverything) {
    g.text("You found the last terminal!\nGreat job!", g.width/2, textY);
  }
}

//===================================================
void renderScene(PGraphics g) {
  // or is it without the g.? 
  g.lights();

  switch(state) {
    //---------------------------------------------
  case FADE_IN_PREVIOUS:
    mAnim.pixelateIn(prevModel.mask);
    prevModel.render(g); 
    if (mAnim.done) {
      mAnim.reset();
      state = State.FADE_IN_WAIT;
      timer = new Timer(1000);
    }
    break;

    //---------------------------------------------
  case FADE_IN_WAIT:
    prevModel.render(g); 
    if (timer.isFinished()) state = State.FADE_IN_CURRENT;
    break;

    //---------------------------------------------
  case FADE_IN_CURRENT:
    mAnim.pixelateIn(model.mask);
    mAnim.reverse(prevModel.mask, model.mask);
    prevModel.render(g);
    model.render(g); 
    if (mAnim.done) {
      state = State.SPIN;
      timer = new Timer(1000 * TIMEOUT); // one minute before timeout 
      spinSpeed = 0;
      fadeOut = 1;
    }
    break;

    //---------------------------------------------
  case SPIN:
    spinAngle += spinSpeed;
    if (spinSpeed < 0.005) spinSpeed += 0.0001; 
    if (timer.isFinished()) {
      if (fadeOut > 0) fadeOut -= 0.01;
      else {
        state = State.IDLE;
      }
    }

    model.renderFast(g); // use the cache
    break;

    //---------------------------------------------
  case IDLE:
    showAlreadyVisited = false;
    showFoundEverything = false;
    spinSpeed = 0.005;
    spinAngle += spinSpeed;
    arrow.renderFast(g);
    break;
  }
}

//===================================================
// DEBUG 
void drawMask(float[][] mask, float xx, float yy) {
  pushMatrix();
  translate(xx, yy);

  for (int i=0; i < mask.length; i++) {
    for (int j=0; j < mask[0].length; j++) {
      float x = map(i, 0, 50, 0, 50*5); 
      float y= map(j, 0, 50, 0, 50*5);      
      fill(mask[j][i]*255);
      stroke(128);
      rect(x, y, 5, 5);
    }
  }

  popMatrix();
}

//===================================================
// Called when a scan event is received over OSC
void scan(String code) {       
  println("Received code: " + code);
  code = code.substring(0, 4); // temporary fix -> trim to 4 characters

  String area = areaNames[int(random(0, 4))];
  String url = "http://osc.rtanewmedia.ca/character-update/" + code + "/" + area;  
  println("using random area:" + area);

  PImage img = null;
  if (code.equals("abcd")) img = loadImage("test.png");
  else {
    img = loadImage(url, "png");
  }

  SpriteSheet s = new SpriteSheet(img);

  if (s.hasVisitedAll()) {
    showFoundEverything = true;
  } else if (s.hasVisited(area)) {
    println("Already visited");  
    showAlreadyVisited= true;
  }




  int stage = 0; // TODO: get from Sprite sheet
  sounds.playSong(stage);   

  // Update the model objects
  prevModel.setImage(s.pFront, s.pFront_d, s.pBack, s.pBack_d);  
  model.setImage(s.front, s.front_d, s.back, s.back_d);

  // Start the animation 
  state = State.FADE_IN_PREVIOUS;
  spinAngle = -PI/2;
  mAnim.reset();

  // TODO start in a different state IF this is an already visited station
}



//===================================================
CornerPinSurface ap;
color ac = color(0, 255, 0);
color dc = color(255);
boolean lockSides = false;
float moveBy = 10;

void keyPressed() {
  switch(key) {
  case ' ':
    scan("abcd");
    break;
  case 'c':
    cursor();
    ks1.toggleCalibration();
    break;
  case 's':
    ks1.save();
    break;
  case 'l':
    ks1.load();
    break;

  case 'v':
    showAlreadyVisited = !showAlreadyVisited;
    break;

  case 'w':
    showFoundEverything = !showFoundEverything;    
    break;

  case '1':   
    ap.setGridColor(dc);
    ap = surface1;
    ap.setGridColor(ac);
    break;


  case '2':   
    ap.setGridColor(dc);
    ap = surface2;
    ap.setGridColor(ac);
    break;

  case '3':   
    ap.setGridColor(dc);
    ap = surface3;
    ap.setGridColor(ac);
    break;

  case 'z':
    lockSides = false;
    break;
  case 'Z':
    lockSides = true;
    break;

  case CODED:
    moveSurface();
    break;

  case '+':
    moveBy += 1;
    break;

  case '-':
    if (moveBy >0) moveBy -= 1;
    break;

  case 'x':
    scaleSurface(2);
    break;
  case 'X':
    scaleSurface(-2);
    break;
  }
}

// Not working.
void scaleSurface(float sf) {
}

void moveSurface() {

  if (ks1.isCalibrating()) {


    float x = ap.x;
    float y = ap.y;
    float m = moveBy;

    if (keyCode == UP) y -= m;
    if (keyCode == DOWN) y += m;
    if (keyCode == LEFT) x -= m;
    if (keyCode == RIGHT) x += m;


    ap.moveTo(x, y);

    if (lockSides) {
      if (ap == surface1) surface3.moveTo(surface3.x, ap.y);
      if (ap == surface3) surface1.moveTo(surface1.x, ap.y);
    }
  }
  else {
    if (keyCode == UP) textY -= 5;
    if (keyCode == DOWN) textY += 5;
  }
}