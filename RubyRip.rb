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
  
  def initialize(address,port,output_dir)
    
    @address      = address                       #Address to connect to
    @port         = port                          #Port number to connect to   
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
  
  #Connects to the server
  def connect   
    @connection = TCPSocket.new(@address,@port) #Connects to the server
    send_metadata_request
    receive
  end
  
  private
  
  #Sends a meta data request to the server
  def send_metadata_request
     httpReq = "GET / HTTP/1.1\r\nHost: #{@address}\r\nConnection: close\r\n" +
               "icy-metadata: 1\r\ntransferMode.dlna.org: Streaming\n\r\nHEAD / HTTP/1.1\r\n" +
               "Host: #{@address}\r\n" + "User-Agent: RubyRipper\n\r\n";
               
     @connection.puts httpReq
  end
  
  def receive
    
    while line = @connection.gets
      
      line.each_byte do |b|
        
        if @offset >= @BUFFER_SIZE
          @counter += @offset
          proccess_data #Process the buffer
          @offset = 0
        end
        
        @buffer[@offset] = b
        @offset += 1
        
      end
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
          end
        end
      end
      
      #Writes all data in the buffer that isn't meta data
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


ripper = Ripper.new("208.43.81.168",8745,"/home/chuck/")
ripper.connect

