/*  OctoWS2811 movie2serial.pde - Transmit video data to 1 or more
      Teensy 3.0 boards running OctoWS2811 VideoDisplay.ino
    http://www.pjrc.com/teensy/td_libs_OctoWS2811.html
    Copyright (c) 2018 Paul Stoffregen, PJRC.COM, LLC

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.
*/

// Linux systems (including Raspberry Pi) require 49-teensy.rules in
// /etc/udev/rules.d/, and gstreamer compatible with Processing's
// video library.

// To configure this program, edit the following sections:
//
//  1: change myMovie to open a video file of your choice    ;-)
//
//  2: edit the serialConfigure() lines in setup() for your
//     serial device names (Mac, Linux) or COM ports (Windows)
//
//  3: if your LED strips have unusual color configuration,
//     edit colorWiring().  Nearly all strips have GRB wiring,
//     so normally you can leave this as-is.
//
//  4: if playing 50 or 60 Hz progressive video (or faster),
//     edit framerate in movieEvent().

import processing.video.*;
import processing.serial.*;
import java.awt.Rectangle;

Movie myMovie;

float gamma = 1.7;

int numPorts=0;  // the number of serial ports in use
int maxPorts=2; // maximum number of serial ports

Serial[] ledSerial = new Serial[maxPorts];     // each port's actual Serial port
Rectangle[] ledArea = new Rectangle[maxPorts]; // the area of the movie each port gets, in % (0-100)
boolean[] ledLayout = new boolean[maxPorts];   // layout of rows, true = even is left->right
PImage[] ledImage = new PImage[maxPorts];      // image sent to each port
int[] gammatable = new int[256];
int errorCount=0;
float framerate=0;
ArrayList<ImagePixels> imagepixels = new ArrayList<ImagePixels>();
//ArrayList<ImagePixels> newimagepixels = new ArrayList<ImagePixels>();
StringDict newimagepixels = new StringDict();
IntDict originalimagepixels = new IntDict();

class ImagePixels{
  float xPos, yPos;
  boolean inCircle;
  public ImagePixels(float xPos, float yPos, boolean inCircle){
    this.xPos = xPos;
    this.yPos = yPos;
    this.inCircle = inCircle; 
  }
}

class remapImage{
  int new_map_index_start;
  int original_map_index_start;
  int original_map_index_end;
  int counter;
  boolean flipped;
  
  public remapImage(){ 
  }
  void remap_helper(int i, int original_map_index){
     if(counter == 16 && flipped == false){
        //println("flipped 1");
        flipped = true;
        new_map_index_start = ((i+1) * 32) - 1;
      }
      if(originalimagepixels.get(str(original_map_index)) == 1){
         //println(str(i) + "   "  + str(new_map_index_start) + "," + str(original_map_index_start) ); 
          newimagepixels.set(str(new_map_index_start), str(original_map_index));
          //println(str(new_map_index_start));
          //left to right
          if(flipped == false){
            new_map_index_start += 1;
            counter += 1;
          }
          //right to left
          if(flipped == true){
            new_map_index_start -= 1;
            //println(str(new_map_index_start));
          }
      }
      
  }
  void remap(){
    // number of rows used on teensy
    for(int i=0; i<8; i++){
      new_map_index_start = i * 32;
      original_map_index_start = i * 32;
      original_map_index_end = ((i+1) * 32) - 1;
      counter = 0;
      flipped = false;
      // 32 LEDs split in half
      // LEDs index 0 to 15
      for(int a=0; a<16; a++){
        original_map_index_start += 1;
        remap_helper(i, original_map_index_start);
      }
      // LEDs index 31 to 16
      for(int b=0; b<16; b++){
        original_map_index_end -= 1;
        remap_helper(i, original_map_index_end);
      }
    }
  }
}

void settings() {
  size(500, 700);  // create the window
}

void setup() {
  String[] list = Serial.list();
  delay(20);
  println("Serial Ports List:");
  println(list);
  serialConfigure("/dev/tty.usbmodem89789301");  // change these to your port names
  serialConfigure("/dev/tty.usbmodem111288301");
  if (errorCount > 0) exit();
  for (int i=0; i < 256; i++) {
    gammatable[i] = (int)(pow((float)i / 255.0, gamma) * 255.0 + 0.5);
  }
  
  myMovie = new Movie(this, "/Users/artarazavi/Desktop/movie2serial/data/trip.mov");
  myMovie.loop();  // start the movie :-)
  
  ellipseMode(CENTER);
}

void getFrame() {
  PImage img = get(0,200,500,500);
  for (int i=0; i < numPorts; i++) {
    // copy a portion of the movie's image to the LED image
    int xoffset = percentage(img.width, ledArea[i].x);
    int yoffset = percentage(img.height, ledArea[i].y);
    int xwidth =  percentage(img.width, ledArea[i].width);
    int yheight = percentage(img.height, ledArea[i].height);
    ledImage[i].copy(img, xoffset, yoffset, xwidth, yheight,
                     0, 0, ledImage[i].width, (ledImage[i].height));
    
    // convert the LED image to raw data
    byte[] ledData =  new byte[(ledImage[i].width * ledImage[i].height * 3) + 3];
    image2data(ledImage[i], ledData, ledLayout[i]);
    if (i == 0) {
      ledData[0] = '*';  // first Teensy is the frame sync master
      int usec = (int)((1000000.0 / framerate) * 0.75);
      ledData[1] = (byte)(usec);   // request the frame sync pulse
      ledData[2] = (byte)(usec >> 8); // at 75% of the frame time
    } else {
      ledData[0] = '%';  // others sync to the master board
      ledData[1] = 0;
      ledData[2] = 0;
    }
    // send the raw data to the LEDs  :-)
    ledSerial[i].write(ledData);
  }
}


// movieEvent runs for each new frame of movie data
void movieEvent(Movie m) {
  //println("movieEvent");
  // read the movie's next frame
  m.read();

  //if (framerate == 0) framerate = m.getSourceFrameRate();
  framerate = 30.0; // TODO, how to read the frame rate???

}

// image2data converts an image to OctoWS2811's raw data format.
// The number of vertical pixels in the image must be a multiple
// of 8.  The data array must be the proper size for the image.
void image2data(PImage image, byte[] data, boolean layout) {
  int offset = 3;
  int x, y, xbegin, xend, xinc, mask;
  int linesPerPin = image.height/8;
  int pixel[] = new int[8];
  for (y = 0; y < linesPerPin; y++) {
    if ((y & 1) == (layout ? 0 : 1)) {
      // even numbered rows are left to right
      xbegin = 0;
      xend = image.width;
      xinc = 1;
    } else {
      // odd numbered rows are right to left
      xbegin = image.width - 1;
      xend = -1;
      xinc = -1;
    }
    
    for (x = xbegin; x != xend; x += xinc) {
      for (int i=0; i < 8; i++) {
        // fetch 8 pixels from the image, 1 for each pin
        //pixel[i] = image.pixels[x + (y + linesPerPin * i) * image.width];
        int pixelnum =  x + (y + linesPerPin * i) * image.width;
        //println(pixelnum);
        //if(newimagepixels.hasKey(str(pixelnum))){
        if(originalimagepixels.get(str(pixelnum)) == 1){
          //int imagemapping = int(newimagepixels.get(str(pixelnum)));
          pixel[i] = image.pixels[pixelnum];
          pixel[i] = colorWiring(pixel[i]);
          //println(str(pixelnum) + " , " + str(imagemapping) + " , " + str(pixel[i]));
        }
        
        //println(newimagepixels.valueArray());
        //pixel[i] = image.pixels[x + (y + linesPerPin * i) * image.width];

      }
      // convert 8 pixels to 24 bytes
      for (mask = 0x800000; mask != 0; mask >>= 1) {
        byte b = 0;
        for (int i=0; i < 8; i++) {
          if ((pixel[i] & mask) != 0) b |= (1 << i);
        }
        data[offset++] = b;
      }
    }
  }
  //println(data.length);
}

// translate the 24 bit color from RGB to the actual
// order used by the LED wiring.  GRB is the most common.
int colorWiring(int c) {
  int red = (c & 0xFF0000) >> 16;
  int green = (c & 0x00FF00) >> 8;
  int blue = (c & 0x0000FF);
  red = gammatable[red];
  green = gammatable[green];
  blue = gammatable[blue];
  return (green << 16) | (red << 8) | (blue); // GRB - most common wiring
}

// ask a Teensy board for its LED configuration, and set up the info for it.
void serialConfigure(String portName) {
  if (numPorts >= maxPorts) {
    println("too many serial ports, please increase maxPorts");
    errorCount++;
    return;
  }
  try {
    ledSerial[numPorts] = new Serial(this, portName);
    if (ledSerial[numPorts] == null) throw new NullPointerException();
    ledSerial[numPorts].write('?');
  } catch (Throwable e) {
    println("Serial port " + portName + " does not exist or is non-functional");
    errorCount++;
    return;
  }
  delay(50);
  String line = ledSerial[numPorts].readStringUntil(10);
  if (line == null) {
    println("Serial port " + portName + " is not responding.");
    println("Is it really a Teensy 3.0 running VideoDisplay?");
    errorCount++;
    return;
  }
  String param[] = line.split(",");
  if (param.length != 12) {
    println("Error: port " + portName + " did not respond to LED config query");
    errorCount++;
    return;
  }
  // only store the info and increase numPorts if Teensy responds properly
  ledImage[numPorts] = new PImage(Integer.parseInt(param[0]), Integer.parseInt(param[1]), RGB);
  ledArea[numPorts] = new Rectangle(Integer.parseInt(param[5]), Integer.parseInt(param[6]),
                     Integer.parseInt(param[7]), Integer.parseInt(param[8]));
  ledLayout[numPorts] = (Integer.parseInt(param[2]) == 0);
  //println(ledLayout);
  numPorts++;
}

// draw runs every time the screen is redrawn - show the movie...
void draw() {
  //println("draw");
  // show the original video
  image(myMovie, 0, 200, 500, 500);
  
  // draw a circle
  
  noStroke();
  fill(255,0,0);
  rect(250,450,250,250);
  fill(0,0,255);
  rect(0,200,250,250);
  noFill();  // Set fill to transparrent
  //ellipse (x,y,d1,d2)
  stroke(250);
  //ellipse(250, 450, 500, 500);
  
  //grid + pixels
  populateGrid();
  remapImage image1 = new remapImage();
  image1.remap();
  
  getFrame();
  
  // then try to show what was most recently sent to the LEDs
  // by displaying all the images for each port.
  for (int i=0; i < numPorts; i++) {
    // compute the intended size of the entire LED array
    int xsize = percentageInverse(ledImage[i].width, ledArea[i].width);
    int ysize = percentageInverse(ledImage[i].height, ledArea[i].height);
    // computer this image's position within it
    int xloc =  percentage(xsize, ledArea[i].x);
    int yloc =  percentage(ysize, ledArea[i].y);
    // show what should appear on the LEDs
    image(ledImage[i], 250 - xsize / 2 + xloc, 10 + yloc);
  }
  
}

void populateGrid(){
  //grid + pixels
  float dist_lines_across = width / 16;
  for(int i=0; i<16; i++){
    stroke(255);
    // grid
    //line(i*dist_lines_across, 200, i*dist_lines_across, height);
    //line(0, 200 + i*dist_lines_across, width, 200 + i*dist_lines_across); 
    
    float half_dist = dist_lines_across / 2;
    for(int j=0; j<16; j++){
      float x = (i*dist_lines_across) +half_dist;
      float y = 200 + (j*dist_lines_across) +half_dist;
      boolean inCircle=inCircle(x,y);
      int index = (j * 16) + i;
      // pixels
      if(inCircle){
        stroke(100);
        inCircle = true;
        originalimagepixels.set(str(index), 1);
        //ellipse(x, y, 5, 5);
      }else{
        stroke(255);
        originalimagepixels.set(str(index), 0);
        //ellipse(x, y , 5, 5);
      }
      
    }
  }
  originalimagepixels.set(str(4), 1);
  originalimagepixels.set(str(11), 1);
  originalimagepixels.set(str(260), 1);
  originalimagepixels.set(str(267), 1);
  //println(originalimagepixels);
}

boolean inCircle(float x1, float y1){
  float halfway = width/2;
  if (dist(x1, y1, halfway, halfway + 200) > halfway) {
    return false;
  }
  else{
    return true;
  }
}

// respond to mouse clicks as pause/play
//boolean isPlaying = true;
//void mousePressed() {
//  if (isPlaying) {
//    myMovie.pause();
//    isPlaying = false;
//  } else {
//    myMovie.play();
//    isPlaying = true;
//  }
//}

// scale a number by a percentage, from 0 to 100
int percentage(int num, int percent) {
  double mult = percentageFloat(percent);
  double output = num * mult;
  return (int)output;
}

// scale a number by the inverse of a percentage, from 0 to 100
int percentageInverse(int num, int percent) {
  double div = percentageFloat(percent);
  double output = num / div;
  return (int)output;
}

// convert an integer from 0 to 100 to a float percentage
// from 0.0 to 1.0.  Special cases for 1/3, 1/6, 1/7, etc
// are handled automatically to fix integer rounding.
double percentageFloat(int percent) {
  if (percent == 33) return 1.0 / 3.0;
  if (percent == 17) return 1.0 / 6.0;
  if (percent == 14) return 1.0 / 7.0;
  if (percent == 13) return 1.0 / 8.0;
  if (percent == 11) return 1.0 / 9.0;
  if (percent ==  9) return 1.0 / 11.0;
  if (percent ==  8) return 1.0 / 12.0;
  return (double)percent / 100.0;
}
