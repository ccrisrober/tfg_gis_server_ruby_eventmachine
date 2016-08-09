=begin
Copyright (c) 2015, maldicion069 (Cristian Rodríguez) <ccrisrober@gmail.con>
//
Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.
//
THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
=end

require "eventmachine"
require "json"
require 'thread'

require_relative "key_object"
require_relative "map"
require_relative "object_user"
require_relative "concurrent_hash"

# file:///C:/Users/Cristian/Downloads/28253878-EventMachine-scalable-non-blocking-i-o-in-ruby.pdf

puts "Try to init server ..."

port = 8089

require 'mysql2'
# https://github.com/brianmario/mysql2

puts "Select Server Mode (S/s) Game Mode / (_) Test Mode: "
opc = gets()
$isGame = false
if opc == "s" || opc == "S" then
  $isGame = true
end

if $isGame then
  puts("Open in Game Mode")
else
  puts("Open in Test Mode")
end

module Server

  puts "Try to connect Mysql..."
  @@client = Mysql2::Client.new(:host => "localhost", :username => "root", :password => "", :database=> "tfg_gis")
  puts "MySQL connection succesfull"

  @@sockets ||= {}

  @@client.query("UPDATE `users` SET `isAlive`=0;")

  results = @@client.query("SELECT o.color, o.id, om.posX, om.posY, om.admin FROM object_map om INNER JOIN object o ON o.id = om.id_obj WHERE om.id_map=1;")
  results.each do |row|
    $RealObjects[row["id"]] = KeyObject.new(row["id"], row["posX"], row["posY"], row["color"])
  end

  results2 = @@client.query("SELECT * FROM `map` WHERE `id`= 1;")
  objects = ConcurrentHash.new
  results.each do |row|
    if $RealObjects[row["id"]] && row["admin"] == "" then
      objects[row["id"].to_s] = $RealObjects[row["id"]]
    end
  end
  puts objects.length()

  @@maps = Array::new

  results2.each do |row|
    @@maps.push(Map.new(row["id"], row["mapFields"], row["width"], row["height"], objects))
  end

  def send_position
    @@sockets[@identifier].send_data(@user.to_json)
  end


  # When new client has been entablished
  def post_init
    @client = Mysql2::Client.new(:host => "localhost", :username => "root", :password => "", :database=> "tfg_gis")
    # @identifier = self.object_id

    # @user = ObjectUser.new(@identifier, "320", "320")
    # msg = {"Action" => "new", "Id" => @user.id,
    #       "X" => @user.pos_x.to_f, "Y" => @user.pos_y.to_f}.to_json
    # @@sockets.each do |id, client|
    #   # Send the message from the client to all other clients
    #   client.send_data msg
    # end
    #
    # @@sockets.merge!({@identifier => self})


    # @@positions[@identifier] = @user

    # send_data ({"Action" => "sendMap", "Map" => @@maps[0],
    # "X" => 5*64, "Y" =>  5*64, "Id" => @identifier,
    # "Users" => @@positions}.to_json)
  end

  def random_value(min, max)
    rand(max - min) + min
  end

  def send_die_player_and_winner_to_show receiver_id
    emisor_id = @user.id
    # And the winner is ...
    winner = -1
    value_c = -1
    value_e = -1

    emisor_roll = nil
    receiver_roll = nil

    results = @client.query('SELECT `port`, `rollDice` FROM `users` WHERE `port`="' + emisor_id + '" or `port`=' + receiver_id + ';')
    results.each do |row|
      if row["port"] == emisor_id then
        emisor_roll = row["rollDice"]
      elsif row["port"] == receiver_id then
        receiver_roll = row["rollDice"]
      end
    end


    if receiver_roll == nil then
      winner = emisor_id
      value_e = emisor_roll
    elsif emisor_roll == nil then
      winner = receiver_id
      value_c = receiver_roll
    elsif emisor_roll > receiver_roll then
      winner = emisor_id
      value_e = emisor_roll
      value_c = receiver_roll
    elsif receiver_roll > emisor_roll then
      winner = receiver_id
      value_e = emisor_roll
      value_c = receiver_roll
    end

    ret = {"Action" => "finishBattle", "ValueClient" => value_c, "ValueEnemy" => value_e, "Winner" => winner}.to_json
    sock.write(ret)
  end

  def send_fight_to_another_client receiver_id
    emisor_id = @user.id
    ret_others = {"Action" => "hide", "Ids" => [emisor_id, receiver_id]}.to_json

    # Save die roll value from emisor_id
    @user.roll_die = random_value(1, 6)
    # @@positions[emisor_id] = @user

    @@sockets.each do |id, client|
      if id == receiver_id then
        ret = {"Action" => "fight", "Id_enemy" => emisor_id}.to_json
        @@positions[receiver_id].roll_die = random_value(1, 6)
        client.send_data ret
      else
        # Otherwise, we send a message to hide the fighters
        client.send_data ret_others
      end
    end

    @descriptors.each do |client|
      if client != @serverSocket then
        if client.peeraddr[1] == receiver_id then
          ret = {"Action" => "fight", "Id_enemy" => emisor_id}.to_json
          @@positions[receiver_id].roll_die = random_value(1, 6)
          client.write(ret)
        else
          # Otherwise, we send a message to hide the fighters
          client.write(ret_others)
        end
      end
    end
  end

  # When receive incoming data from the client
  def receive_data (msg)

    begin
      puts msg

      parsed = JSON.parse(msg)
      action = parsed["Action"]

      if "initWName" === action
        insOrUpd = 1 # 0: ins, 1: upd
        posX = 320
        posY = 320
        @username = parsed["Name"]
        result = @client.query('SELECT `posX`, `posY` FROM `users` WHERE `username`="' + @username  + '"')

        if not result.first
          insOrUpd = 0
        end

        @identifier = self.object_id

        if not result.first
          insOrUpd = 0
          puts "INSERT"
          @client.query("INSERT INTO `users` (`port`, `username`) VALUES ('" + @identifier.to_s + "', '" + @username + "');")
        else
          puts "UPDATE"
          posX = result.first["posX"]
          posY = result.first["posY"]
          @client.query("UPDATE `users` SET `port`=" + @identifier.to_s + ", `isAlive`=1 WHERE `username`='" + @username + "';")
        end

        users = {}

        results = @client.query("SELECT `port`, `posX`, `posY` FROM `users` WHERE `isAlive`=1 AND `port` NOT IN (" + @identifier.to_s + ");")
        results.each do |row|
          users[row["port"].to_s] = ObjectUser.new(row["port"], row["posX"], row["posY"])
        end

        # @@sockets.merge!({@identifier => self})
        send_data ({"Action" => "sendMap", "Map" => @@maps[0],
             "X" => posX, "Y" =>  posY, "Id" => @identifier,
             "Users" => users}.to_json + "\n")

        if $isGame then
          msg = {"Action" => "new", "Id" => @identifier, "PosX" => posX, "PosY" => posY}.to_json
        end
      elsif "move" === action
        pos_x = parsed["Pos"]["X"]
        pos_y = parsed["Pos"]["Y"]
        #Thread.new(isGame) {
        @client.query("UPDATE `users` SET `port`=" + @identifier.to_s + ",`posX`=" +
            pos_x.to_s + ",`posY`=" + pos_y.to_s + " WHERE `port`=" + @identifier.to_s + ";")
        if not $isGame then
          send_data(msg)
        end
        #}
      elsif "position" == action
        send_position
        return
      elsif "fight" == action
        send_fight_to_another_client parsed["Id_enemy"]
        return
      elsif "finishBattle" == action
        send_die_player_and_winner_to_show parsed["Id_enemy"]
        return
      elsif "getObj" == action
        ret = @@maps[0].remove_key parsed["Id_obj"]
        puts ret
        if ret
          Thread.new { 
            res = @client.query("UPDATE `object_map` SET `admin`='" + @username + "' WHERE `id`="+ parsed["Id_obj"].to_s + " AND `id_map`=1;")
          }
          send_data ({"Action" => "getObjFromServer", "Id" => parsed["Id_obj"], "OK" => 1}.to_json)
          ret = @@maps[0].remove_key parsed["Id_obj"]
          parsed.delete "Id_user"
          puts "GET OBJ"
          msg = parsed.to_json
        elsif
          send_data({"Action" => "getObjFromServer", "Id" => parsed["Id_obj"], "OK" => 0}.to_json)
          puts "NOT GET OBJ"
          return
        end
      elsif "freeObj" == action
        parsed["Action"] = "addObj"
        obj = @maps[0].add_key(parsed["Obj"]["Id_obj"], parsed["Obj"]["PosX"], parsed["Obj"]["PosY"])
        @user.remove_object parsed["Obj"]["Id_obj"]
        @@positions[@user.id] = @user
        parsed.delete("Id_user")
        msg = parsed.to_json
      elsif "exit" == action
        puts "EXIT"
        puts $isGame
        if not $isGame then
          send_data(msg + "\n")
        end
        
        # @@positions.delete(@user.id)
        puts "EXIT!!"
        unbind
        return
      end # if -else ..

      # Send the message from the client to all other clients
      if $isGame then
        Thread.new {
          puts "Envío #{msg}"
          @@sockets.each do |id, client|
            if id != @identifier
              client.send_data "#{msg}"
            end
          end
        }
      end

    rescue Exception => e
      puts e
    end

  end

  def unbind
    puts "Erase #{@identifier}"
    puts @@sockets.length
    @@sockets.delete(@identifier)
    puts @@sockets.length
    msg = {"Action" => "exit", "Id" => @identifier}.to_json
    Thread.new {
      @client.query("UPDATE `users` SET `isAlive`=0 WHERE `port`=" + @identifier.to_s + ";")
    }
    Thread.new {
      @@sockets.each do |id, client|
        # Send the message from the client to all other clients
        client.send_data msg
      end
    }
    # EventMachine.stop_event_loop
  end
end

# Started a server in 8089
EventMachine::run do
  EventMachine::start_server "localhost", port, Server
  puts "Running server on "
  puts port
end
