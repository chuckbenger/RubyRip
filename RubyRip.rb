##############################################################################
#  Copyright 2012 cbenger.                                                   #  
#                                                                            #
#  Licensed under the Apache License, Version 2.0 (the "License");           #
#  you may not use this file except in compliance with the License.          #
#  You may obtain a copy of the License at                                   #
#                                                                            #
#       http://www.apache.org/licenses/LICENSE-2.0                           #
#                                                                            #
#  Unless required by applicable law or agreed to in writing, software       #
#  distributed under the License is distributed on an "AS IS" BASIS,         #
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  #
#  See the License for the specific language governing permissions and       #
#  limitations under the License.                                            #
#  under the License.                                                        #
#  Class  => Ripper                                                          #
#  Purpse => Download mp3 streams from Shoutcast servers                     #
##############################################################################

require 'socket'


class Ripper
  
   
  
  #Initializer for Ripper
  def initialize(output_dir)
    
    @address      = ""                            #Address to connect to
    @port         = 0                             #Port number to connect to   
    @output_dir   = output_dir                    #Output directory for downloads
    @BUFFER_SIZE  = 1024                          #Amount to buffer before processing
    @LENGTH_SCALER= 16                            #Amount to scale length field by
    @BADCHARS     = /[\x00\/\\:\*\?\"<>\|]/       #Bad file name characters
    @buffer       = Array.new(@BUFFER_SIZE)       #Buffers data
    @counter      = 0                             #Counter for number of bytes read
    @metaint      = 0                             #Interval in which meta data is sent
    @current_song = ""                            #The currently playing song
    @station_name = ""                            #The name of the station connected to
    @offset       = 0                             #Offset into buffer
    @first_read   = true                          #If true initial meta data will be read
    @file_writer  = nil                           #Writes stream data to file
    
  end
  
  #Connects to the server using given ip address and port number
  def connect(address, port)
    
    #If ip or port number are invalid display error message and return
    (puts "IP address #{address} is invalid"   ;return)  if !validate_ip address
    (puts "Port number #{port} is out of range";return)  if !validate_port port
    
    @address    = address
    @port       = port
    
    begin
      @connection = TCPSocket.new(@address,@port) #Connects to the server
      send_metadata_request #Sends a http meta data request to server
      receive               #Starts receiveing data
    rescue Exception => msg
      puts "Error connecting to #{@address}:#{@port} #{msg}"
    end
  end
  
  #Disconnect from the stream
  def disconnect
    @connection.close if !@connection.closed?
  end
  
  #Basic ip address validation
  def validate_ip address
   (address =~ /^(\d{1,3}\.){3}\d{1,3}$/) != nil
  end
  
  #Port number within range validation
  def validate_port port
    (port > 0 && port <= 65535)
  end
  
  private
  
  #Sends a http request to the server to initialize streaming
  def send_metadata_request
     httpReq = "GET / HTTP/1.1\r\nHost: #{@address}\r\nConnection: close\r\n" +
               "icy-metadata: 1\r\ntransferMode.dlna.org: Streaming\n\r\nHEAD / HTTP/1.1\r\n" +
               "Host: #{@address}\r\n" + "User-Agent: RubyRipper\n\r\n";
               
     @connection.puts httpReq
  end
  
  #Receives incoming data from server
  def receive
    
    begin
       while line = @connection.gets
      
        line.each_byte do |b|
        
          #If the current offset if greater than the bufer size
          #process the current data and reset the counter
          if @offset >= @BUFFER_SIZE
            @counter += @offset
            proccess_data #Process the buffer
            @offset = 0
          end
        
          @buffer[@offset] = b
         @offset += 1
        end
      end
    rescue Exception => msg
      puts "Error receiving data => #{msg}"
    end
  end
  
  #Processes the data in the buffer
  def proccess_data
    
    parse_metadata_info if @first_read #If first read parse the meta data information
    
    if @counter >= @metaint
      
      position = @offset - (@counter - @metaint)        #Position field
      length   = @buffer[position + 1] * @LENGTH_SCALER #Lenth of meta data field 
      
      if length > 0
        
        meta_data = @buffer.pack("C*")[position..position + length] #Grabs the meta data from the buffer
        
        meta_data.split(";").each do |attribute|
          
          if attribute.include? "StreamTitle"
            @current_song = attribute.split("=")[1].gsub(@BADCHARS,"_")         #Parses the file name and removes bad characters
            @file_writer  = File.new(@output_dir + @current_song + ".mp3","wb") #Opens a new file to write
            puts "Downloading => #{@current_song}"
          end
        end
      end
      
      #Writes all data at the beginning of the buffer and data after the metadata
      if @file_writer != nil
        @file_writer.write(@buffer[0..position].pack("C*"))                                                 
        @file_writer.write(@buffer[(position + length + 1)..(@offset - (position + length) - 1)].pack("C*"))
      end
      
      @counter = @offset - (position + length + 1); #Adjusts the counter
    end
    @file_writer.write(@buffer.pack("C*")) if @file_writer != nil
  end
  
  #Parses metadata information from buffer
  def parse_metadata_info
    @first_read       = false
    icy_name          = "icy-name:"        #Name of the station field
    icy_meta_interval = "icy-metaint:"     #Rate in which metadata is sent
    icy_bitrate       = "icy-br:"          #Bitrate of the stream
    data              = @buffer.pack("C*") #Data in string form
    
    #Loops through each field parsing the data
    data.split("\n").each do |item|
      @station_name = item[icy_name.length..item.length]                                   if item.include? icy_name
      @metaint      = item[icy_meta_interval.length..item.length].to_i                     if item.include? icy_meta_interval
      @counter     -= data[0..data.index(icy_bitrate) + item.length].bytes.to_a.length + 1 if item.include? icy_bitrate
    end
  end
end


ripper = Ripper.new("/home/chuck/Music/s/")
ripper.connect "216.18.227.251",8000



