# typed: strict
# frozen_string_literal: true

module Solana::Ruby::Kit
  module RpcTypes
    extend T::Sig
    # Well-known cluster endpoint URLs.
    MAINNET_URL = T.let('https://api.mainnet-beta.solana.com', String)
    DEVNET_URL  = T.let('https://api.devnet.solana.com',       String)
    TESTNET_URL = T.let('https://api.testnet.solana.com',      String)

    # A cluster-tagged URL string.
    # Mirrors TypeScript's branded string types:
    #   MainnetUrl, DevnetUrl, TestnetUrl, ClusterUrl
    #
    # In Ruby we carry the cluster tag as a symbol on a wrapper struct,
    # since Ruby cannot brand primitive String values.
    class ClusterUrl < T::Struct
      extend T::Sig
      const :url,     String
      const :cluster, T.nilable(Symbol)  # :mainnet | :devnet | :testnet | nil

      sig { returns(String) }
      def to_s = @url
    end

    extend self

    # Wraps a URL string and tags it as mainnet.
    # Mirrors `mainnet(url)`.
    sig { params(url: String).returns(ClusterUrl) }
    def mainnet(url = MAINNET_URL)
      ClusterUrl.new(url: url, cluster: :mainnet)
    end

    # Wraps a URL string and tags it as devnet.
    # Mirrors `devnet(url)`.
    sig { params(url: String).returns(ClusterUrl) }
    def devnet(url = DEVNET_URL)
      ClusterUrl.new(url: url, cluster: :devnet)
    end

    # Wraps a URL string and tags it as testnet.
    # Mirrors `testnet(url)`.
    sig { params(url: String).returns(ClusterUrl) }
    def testnet(url = TESTNET_URL)
      ClusterUrl.new(url: url, cluster: :testnet)
    end

    # Wraps a custom URL with no cluster tag.
    sig { params(url: String).returns(ClusterUrl) }
    def cluster_url(url)
      ClusterUrl.new(url: url, cluster: nil)
    end
  end
end
