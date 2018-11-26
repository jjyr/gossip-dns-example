require 'ciri/p2p/server'
require 'ciri/p2p/protocol'
require 'ciri/key'
require 'json'
require 'async'

# GossipDNS protocol
class GossipDNS < Ciri::P2P::Protocol

  # code of our messages
  FIND_URLS = 1
  NEW_URLS = 2

  attr_reader :dns_records

  def initialize(urls:)
    # set properties for our protocol
    super(name: '2048DNS', version: 1, length: 8096)
    # 2048 urls
    @urls = urls
  end

  def initialized(context)
    puts "Service started!"
    task = Async::Task.current
    # broadcast FIND_URLS request to peers every 10 seconds
    task.reactor.every(10) do
      context.peers.each do |peer|
        task.async do
          context.send_data(FIND_URLS, '', peer: peer)
        end
      end
    end
  end

  def received(context, msg)
    # check msg code
    case msg.code
    when NEW_URLS
      urls = JSON.load(msg.payload)
      puts "receive #{urls.count} urls from #{context.peer.inspect}"
      @urls = (@urls + urls).uniq
    when FIND_URLS
      puts "send #{@urls.count} urls to #{context.peer.inspect}"
      context.send_data(NEW_URLS, JSON.dump(@urls))
    else
      puts "received invalid message code #{msg.code}, ignoring"
    end
    puts "[#{context.local_node_id.short_hex}] current urls:"
    puts @urls
  end

  def connected(context)
    puts "connected new peer #{context.peer.inspect}"
  end

  def disconnected(context)
    puts "disconnected peer #{context.peer.inspect}"
  end
end

def start_node(protocols:, 
               private_key: Ciri::Key.random, 
               bootnodes:, 
               host: '127.0.0.1', tcp_port: 0, udp_port: 0)
  Ciri::P2P::Server.new(
    private_key: private_key, # private key of our node, used for encrypted communication
    protocols: protocols, # install protocols
    bootnodes: bootnodes,
    host: host,
    tcp_port: tcp_port, # node port
    udp_port: udp_port, # port for discovery
    discovery_interval_secs: 5, # try discovery more nodes every 5 seconds
    dial_outgoing_interval_secs: 10, # try connect to new nodes every 10 seconds
    max_outgoing: 4, # number of nodes we will try to connect
    max_incoming: 8, # number of nodes we will accept
  )
end

def start_example
  puts "start example"
  Async::Reactor.run do |task|
    node1_key = Ciri::Key.random
    protocol1 = GossipDNS.new(urls: ['baidu.com'])
    protocol2 = GossipDNS.new(urls: ['google.com'])
    # start node1
    task.async do
      start_node(protocols: [protocol1], private_key: node1_key, bootnodes: [], tcp_port: 3000, udp_port: 3000).run
    end
    # start node2
    task.async do
      node1 = Ciri::P2P::Node.new(
        node_id: Ciri::P2P::NodeID.new(node1_key),
        addresses: [
          Ciri::P2P::Address.new(
            ip: '127.0.0.1',
            udp_port: 3000,
            tcp_port: 3000,
          )
        ]
      )
      start_node(protocols: [protocol2], bootnodes: [node1], tcp_port: 3001, udp_port: 3001).run
    end
  end
end

if caller.size == 0
  Ciri::Utils::Logger.setup(level: :info)
  start_example
end

