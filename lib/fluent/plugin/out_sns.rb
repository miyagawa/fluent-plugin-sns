module Fluent
    
    require 'aws-sdk'

    class SNSOutput < BufferedOutput
        
        Fluent::Plugin.register_output('sns', self)
        
        include SetTagKeyMixin
        config_set_default :include_tag_key, false
        
        include SetTimeKeyMixin
        config_set_default :include_time_key, true
        
        config_param :aws_key_id, :string, :default => nil
        config_param :aws_sec_key, :string, :default => nil
        
        config_param :sns_subject_key, :string, :default => nil
        config_param :sns_subject, :string, :default => nil
        config_param :sns_endpoint, :string, :default => 'sns.ap-northeast-1.amazonaws.com'
        config_param :proxy, :string, :default => ENV['HTTP_PROXY']

        config_param :sns_topic_name, :string, :default => nil
        config_param :sns_topic_map_tag, :bool, :default => false
        config_param :remove_tag_prefix, :string, :default => nil
        config_param :sns_topic_map_key, :string, :default => nil

        def configure(conf)
            super

            @topic_generator = case
                               when @sns_topic_name
                                   lambda { |tag,record| @sns_topic_name }
                               when @sns_topic_map_key
                                   lambda { |tag,record| record[@sns_topic_map_key]}
                               when @sns_topic_map_tag
                                   lambda { |tag,record| tag.gsub(/^#{@remove_tag_prefix}(\.)?/, '')}
                               else
                                   raise Fluent::ConfigError, "no one way specified to decide target"
                               end
        end

        def start
            super
            options = {}
            options[:sns_endpoint] = @sns_endpoint
            options[:proxy_uri] = @proxy
            if @aws_key_id && @aws_sec_key
              options[:access_key_id] = @aws_key_id
              options[:secret_access_key] = @aws_sec_key
            end
            AWS.config(options)
            
            @sns = AWS::SNS.new
            @topics = get_topics
        end
        
        def shutdown
            super
        end

        def format(tag, time, record)
            [tag, time, record].to_msgpack
        end

        def write(chunk)
            chunk.msgpack_each do |tag, time, record|
                record["time"] = Time.at(time).localtime
                subject = record[@sns_subject_key] || @sns_subject  || 'Fluent-Notification'
                topic = @topic_generator.call(tag, record)
                topic = topic.gsub(/\./, '-') if topic # SNS doesn't allow .
                if @topics[topic]
                    @topics[topic].publish(record.to_json, :subject => subject )
                else
                    $log.warn "Could not find topic '#{topic}' on SNS"
                end
            end
        end
        
        def get_topics()
            @sns.topics.inject({}) do |product, topic|
                product[topic.name] = topic
                product
            end
        end
    end
end
