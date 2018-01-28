require "random"
require "./utils"
require "./client"

module ::E2E
  class Runner
    @client : Client

    @node_ports : Array(Int32)

    def initialize(@num_nodes : Int32, @num_miners : Int32)
      raise "@num_nodes has to be grater than 0" if @num_nodes < 0
      raise "@num_nodes of E2E::Runner has to be less than 6" if @num_nodes > 6
      raise "@num_miners of E2E::Runner has to be less than 6" if @num_miners > 6

      @node_ports = (4000..4000 + (@num_nodes - 1)).to_a

      @client = Client.new(@node_ports, @num_miners)
    end

    def pre_build
      STDERR.puts `shards build`
    end

    def launch_nodes
      # genesis node
      node(@node_ports[0], false, nil, 0)

      node_ports_public = [@node_ports[0]]

      sleep 1

      @node_ports[1..-1].each_with_index do |node_port, idx|
        is_private = Random.rand(10) < 2
        connecting_port = node_ports_public.sample

        node(node_port, is_private, connecting_port, idx + 1)
        node_ports_public.push(node_port) unless is_private
        sleep 1
      end
    end

    def kill_nodes
      `pkill -f sushid`
    end

    def launch_miners
      @num_miners.times do |i|
        mining(@node_ports.sample, Random.rand(@num_miners))
      end
    end

    def kill_miners
      `pkill -f sushim`
    end

    def launch_client
      @client.launch
    end

    def kill_client
      @client.kill
    end

    def assertion!
      latest_block_index = @node_ports.map { |port|
        size = blockchain_size(port)
        STDERR.puts "#{port} <- #{size}"
        size - 1
      }.max

      return STDERR.puts yellow("mining is not enough") if latest_block_index < ::Sushi::Core::UTXO::CONFIRMATION - 1

      checking_block_index = latest_block_index - (::Sushi::Core::UTXO::CONFIRMATION - 1)

      block_json = block(@node_ports[0], checking_block_index)

      @node_ports[1..-1].each do |node_port|
        _block_json = block(node_port, checking_block_index)
        raise "Difference block #{block_json} vs #{_block_json}" if block_json != _block_json
      end

      STDERR.puts "Total transactions: #{@client.num_transactions}"
    end

    def run!
      kill_nodes
      kill_miners

      pre_build

      launch_nodes

      sleep 1

      launch_miners

      sleep 1

      launch_client

      sleep 300

      kill_client

      sleep 1

      kill_miners

      sleep 1

      assertion!
    ensure
      kill_nodes
    end

    include Utils
  end
end
