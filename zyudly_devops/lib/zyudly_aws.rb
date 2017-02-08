require "aws-sdk"
require "json"
require "yaml"
require "pp"

class ZyudlyAWS
  attr_accessor :verbose
  attr_reader :region, :env, :user_id
  attr_reader :cf, :ec2, :et, :s3, :sns, :sqs, :kinesis

  def initialize(region,env)
    raise "Invalid region" unless region =~ /^(us-)/
    @region = region
    raise "Invalid Environment" unless env =~ /^(dev|stg|prd)$/
    @verbose = false
    @user_id = Aws::IAM::Client.new(region: @region).get_user.user.user_id
    @cf = Aws::CloudFront::Client.new(region: @region)
    @ec2 = Aws::EC2::Client.new(region: @region)
    @et = Aws::ElasticTranscoder::Client.new(region: @region)
    @kinesis = Aws::Kinesis::Client.new(region: @region)
    @s3 = Aws::S3::Client.new(region: @region)
    @sns = Aws::SNS::Client.new(region: @region)
    @sqs = Aws::SQS::Client.new(region: @region)
  end

  def logr(mesg)
    STDERR.puts "#{Time.now} #{mesg}" if @verbose
  end

  def ec2_list
    logr "== ----------------------------------------------------------------"
    logr "== -- ec2_list starting"
    res = @ec2.describe_instances.reservations
    @instances = []
    res.each do |r|
      r.instances.each do |i|
        @instances << i
      end
    end
    @instances.each do |i|
      next unless i.state.name == "running"
      puts "== -- ***********************************************************"
      puts "== -- ** Tags:"
      i.tags.each do |t|
        puts "== -- **   '#{t.key}' => '#{t.value}'"
      end
      puts "== -- ** Instance ID = '#{i.instance_id}'"
      puts "== -- ** Instance State = '#{i.state.name}'"
      puts "== -- ** Instance Code = '#{i.state.code}'"
      puts "== -- ** Public IP Address = '#{i.public_ip_address}'"
      puts "== -- ** Key Name = '#{i.key_name}'"
      puts "== -- ** Image ID = '#{i.image_id}'"
      puts "== -- ***********************************************************"
    end
    logr "== -- ec2_list finished"
    logr "== ----------------------------------------------------------------"
  end

  def sqs_get_queue_arn(url)
    resp = @sqs.get_queue_attributes({
      queue_url: url,
      attribute_names: ["QueueArn"]
    })
    return resp.attributes["QueueArn"]
  end

  def sqs_create_queue(name,arn)
    policy = {
      "Version"=>"2012-10-17",
      "Id" => "#{arn}/SQSDefaultPolicy",
      "Statement" => [{
        "Sid" => "Sid1439183115411",
        "Effect" => "Allow",
        "Principal" => {"AWS"=>"*"},
        "Action" => "SQS:SendMessage",
        "Resource"=> "#{arn}"
      }]
    }
    resp = @sqs.create_queue({
      queue_name: "#{@env}-#{name}",
      attributes: {
        "DelaySeconds" => "0",
        "ReceiveMessageWaitTimeSeconds" => "0",
        "MaximumMessageSize" => "262144", # 256 KB (in Bytes)
        "VisibilityTimeout" => "60", # One minute (in seconds)
        "MessageRetentionPeriod" => "1209600", # Fourteen Days (in seconds)
        "Policy" => policy.to_json
      }
    })
    return resp.queue_url
  end

  def sqs_list
    resp = @sqs.list_queues
    resp.queue_urls.each do |url|
      puts "== --------------------------------------------------------------"
      puts "== -- url = '#{url}'"
      resp = @sqs.get_queue_attributes({
        queue_url: url,
        attribute_names: [
          "DelaySeconds", "ReceiveMessageWaitTimeSeconds",
          "MaximumMessageSize", "VisibilityTimeout", "MessageRetentionPeriod",
          "Policy"
        ]
      })
      policy = JSON.parse(resp.attributes["Policy"])
      puts "== --------------------------------------------------------------"
    end
  end

  def s3_create_bucket(bucket_name)
    puts "== ----------------------------------------------------------------"
    puts "== -- Creating bucket '#{bucket_name}'"
    resp = @s3.create_bucket({
      acl: "private",
      bucket: "#{bucket_name}",
      create_bucket_configuration: {
        location_constraint: "#{@region}"
      }
    })
    puts "== ----------------------------------------------------------------"
    return true
  end

  def et_create_transcoder_pipeline(et_name, input_bucket, output_bucket)
    role = "arn:aws:iam::#{@user_id}:role/Elastic_Transcoder_Default_Role"
    aws_kms_key_arn = ""
    resp = @et.create_pipeline({
      name: et_name,
      input_bucket: input_bucket,
      role: role,
      aws_kms_key_arn: aws_kms_key_arn,
      content_config: {
        bucket: output_bucket,
        storage_class: "Standard"
      },
      thumbnail_config: {
        bucket: output_bucket,
        storage_class: "Standard"
      }
    })
    return nil if resp.nil?
    return [resp.pipeline.id, resp.pipeline.arn]
  end

  def et_list
    resp = @et.list_pipelines()
    resp.pipelines.each do |p|
      puts "== ----------------------------------------------------------------"
      puts "== -- id = '#{p.id}'"
      puts "== -- arn = '#{p.arn}'"
      puts "== -- name = '#{p.name}'"
      puts "== -- role = '#{p.role}'"
      puts "== -- status = '#{p.status}'"
      puts "== -- input_bucket = '#{p.input_bucket}'"
      puts "== -- output_bucket = '#{p.output_bucket}'"
      puts "== -- aws_kms_key_arn = '#{p.aws_kms_key_arn}'"
      puts "== -- content_config.bucket = '#{p.content_config.bucket}'"
      puts "== -- thumbnail_config.bucket = '#{p.thumbnail_config.bucket}'"
      puts "== -- content_config.permissions = '#{p.content_config.permissions}'"
      puts "== -- content_config.storage_class = '#{p.content_config.storage_class}'"
      puts "== -- thumbnail_config.permissions = '#{p.thumbnail_config.permissions}'"
      puts "== -- thumbnail_config.storage_class = '#{p.thumbnail_config.storage_class}'"
      puts "== ----------------------------------------------------------------"
    end
  end

  def sns_list
    resp = @sns.list_topics
    resp.topics.each do |t|
      puts "== ----------------------------------------------------------------"
      puts "== -- Topic ARN = '#{t.topic_arn}'"
      puts "== -- *************************************************************"
      res2 = @sns.get_topic_attributes({
        topic_arn: t.topic_arn
      })
      attr = JSON.parse(res2.attributes.to_json)
      puts "== -- ** Topic Attributes:"
      %w[Owner DisplayName TopicArn
         SubscriptionsConfirmed SubscriptionsPending SubscriptionsDeleted
      ].each do |k|
        puts "  '#{k}' => '#{attr[k]}'"
      end
      puts "== -- ** Policy:"
      policy = JSON.parse(attr["Policy"])
      pp policy
      puts "== -- ** Effective Delivery Policy:"
      ed_policy = JSON.parse(attr["EffectiveDeliveryPolicy"])
      pp ed_policy
      puts "== -- *************************************************************"
      puts "== -- *************************************************************"
      puts "== -- ** Subscriptions:"
      res3 = @sns.list_subscriptions_by_topic({
        topic_arn: "#{t.topic_arn}"
      })
      pp res3
      puts "== -- *************************************************************"
      puts "== ----------------------------------------------------------------"
    end
  end

  def sns_create_topic(topic_name)
    puts "== ----------------------------------------------------------------"
    resp = @sns.create_topic({
      name: topic_name
    })
    puts "== -- topic_arn = '#{resp.topic_arn}'"
    puts "== ----------------------------------------------------------------"
    return resp.topic_arn
  end

  def sns_set_topic_attributes(topic_arn)
    puts "== ----------------------------------------------------------------"
    @sns.set_topic_attributes({
      topic_arn: topic_arn,
      attribute_name: "DisplayName",
      attribute_value: "#{@env} ET ST"
    })
    policy = {
      "Version" => "2008-10-17",
      "Id" => "__default_policy_ID",
      "Statement" => [
        {
          "Sid" => "__default_statement_ID",
          "Effect" => "Allow",
          "Principal" => { "AWS" => "*" },
          "Action" => [
            "SNS:Subscribe",
            "SNS:ListSubscriptionsByTopic",
            "SNS:DeleteTopic",
            "SNS:GetTopicAttributes",
            "SNS:Publish",
            "SNS:RemovePermission",
            "SNS:AddPermission",
            "SNS:Receive",
            "SNS:SetTopicAttributes"
          ],
          "Resource" => "#{@topic_arn}",
          "Condition" => {
            "StringEquals" => {
              "AWS:SourceOwner" => "#{@user_id}"
            }
          }
        }
      ]
    }
    @sns.set_topic_attributes({
      topic_arn: topic_arn,
      attribute_name: "Policy",
      attribute_value: policy.to_json
    })
    effective_delivery_policy = {
      "http" => {
        "defaultHealthyRetryPolicy" => {
          "minDelayTarget" => 20,
          "maxDelayTarget" => 20,
          "numRetries" => 3,
          "numMaxDelayRetries" => 0,
          "numNoDelayRetries" => 0,
          "numMinDelayRetries" => 0,
          "backoffFunction" => "linear"
        },
        "disableSubscriptionOverrides" => false
      }
    }
    @sns.set_topic_attributes({
      topic_arn: topic_arn,
      attribute_name: "DeliveryPolicy",
      attribute_value: effective_delivery_policy.to_json
    })
    puts "== ----------------------------------------------------------------"
    return true
  end

  def sns_subscribe_topic_to_queue(topic_arn,queue_arn)
    puts "== ----------------------------------------------------------------"
    puts "== sns_subscribe_topic_to_queue starting"
    resp = @sns.subscribe({
      topic_arn: "#{topic_arn}",
      protocol: "sqs",
      endpoint: "#{queue_arn}"
    })
    pp resp
    puts "== -- subscription_arn = '#{resp.subscription_arn}'"
    puts "== sns_subscribe_topic_to_queue finished"
    puts "== ----------------------------------------------------------------"
    return resp.subscription_arn
  end

  def cf_list_origin_access_identities
    puts "== ----------------------------------------------------------------"
    puts "== -- cf_list_origin_access_identities starting"
    puts "== -- Origin access identities:"
    resp = @cf.list_cloud_front_origin_access_identities({})
    resp.cloud_front_origin_access_identity_list.items.each do |i|
      puts "== -- ***********************************************************"
      pp i
      puts "== -- ***********************************************************"
    end
    puts "== -- cf_list_origin_access_identities finished"
    puts "== ----------------------------------------------------------------"
  end

  def cf_list_distributions
    puts "== ----------------------------------------------------------------"
    puts "== -- cf_list_distributions starting"
    resp = @cf.list_distributions({})
    resp.distribution_list.items.each do |i|
      puts "== -- ***********************************************************"
      pp i
      puts "== -- ***********************************************************"
    end
    puts "== -- cf_list_distributions finished"
    puts "== ----------------------------------------------------------------"
  end

  def cf_list_streaming_distributions
    puts "== ----------------------------------------------------------------"
    puts "== -- cf_list_streaming_distributions starting"
    resp = @cf.list_streaming_distributions({})
    resp.streaming_distribution_list.items.each do |i|
      puts "== -- ***********************************************************"
      pp i
      puts "== -- ***********************************************************"
    end
    puts "== -- cf_list_streaming_distributions finished"
    puts "== ----------------------------------------------------------------"
  end

  def create_cf_distribution(s3_bucket_name,caller_reference)
    puts "== ----------------------------------------------------------------"
    puts "== -- create_cf_distribution_for_videos starting"
    resp = @cf.create_cloud_front_origin_access_identity({
      "cloud_front_origin_access_identity_config": {
        "caller_reference": "#{caller_reference}",
        "comment": "#{s3_bucket_name}"
      }
    })
    pp resp
    oai_id = resp.cloud_front_origin_access_identity.id
    resp = @cf.create_distribution({
      distribution_config: {
        "caller_reference": "#{caller_reference}",
        "cache_behaviors": {
          "quantity": 0
        },
        "origins": {
          "quantity": 1,
          "items": [
            {
              "origin_path": "", 
              "s3_origin_config": {
                "origin_access_identity": "origin-access-identity/cloudfront/#{oai_id}"
              },
              "id": "S3-#{s3_bucket_name}",
              "domain_name": "#{s3_bucket_name}.s3.amazonaws.com"
            }
          ],
        },
        "price_class": "PriceClass_All",
        "enabled": true,
        "default_cache_behavior": {
          "trusted_signers": {
            "enabled": false, 
            "quantity": 0
          }, 
          "target_origin_id": "S3-#{s3_bucket_name}",
          "viewer_protocol_policy": "allow-all",
          "forwarded_values": {
            "headers": {
              "quantity": 0
            },
            "cookies": {
              "forward": "none"
            },
            "query_string": false
          },
          "max_ttl": 31536000,
          "smooth_streaming": false,
          "default_ttl": 86400,
          "allowed_methods": {
            "quantity": 2,
            "items": [
              "HEAD",
              "GET"
            ],
            "cached_methods": {
              "items": [
                "HEAD",
                "GET"
              ],
              "quantity": 2
            },
          },
          "min_ttl": 0
        },
        "comment": "", 
        "viewer_certificate": {
          "cloud_front_default_certificate": true,
            "minimum_protocol_version": "SSLv3"
        },
        "custom_error_responses": {
          "quantity": 0
        },
        "restrictions": {
          "geo_restriction": {
            "restriction_type": "none",
            "quantity": 0
          }
        },
        "aliases": {
          "quantity": 0
        }
      }
    })
    puts "== -- create_cf_distribution_for_videos finished"
    puts "== ----------------------------------------------------------------"
  end

  def kinesis_create_stream(stream_name, shard_count=1)
    puts "== ----------------------------------------------------------------"
    puts "== -- kinesis_create_stream starting"
    resp = @kinesis.create_stream({
      stream_name: stream_name,
      shard_count: shard_count
    })
    puts "== -- kinesis_create_stream finished"
    puts "== ----------------------------------------------------------------"
    return resp
  end

  def kinesis_delete_stream(stream_name)
    puts "== ----------------------------------------------------------------"
    puts "== -- kinesis_delete_stream starting"
    resp = @kinesis.delete_stream({
      stream_name: stream_name
    })
    puts "== -- kinesis_delete_stream finished"
    puts "== ----------------------------------------------------------------"
    return resp
  end

  def kinesis_list
    puts "== ================================================================"
    puts "== kinesis_list starting"
    @kinesis.list_streams.stream_names.each do |stream_name|
      puts "== --------------------------------------------------------------"
      puts "== -- stream = '#{stream_name}'"
      resp = @kinesis.describe_stream({
        stream_name: stream_name
      })
      sd = resp.stream_description
      puts "== -- status = '#{sd.stream_status}'"
      puts "== -- num shards = '#{sd.shards.count}'"
      puts "== -- parent shard ID = '#{sd.shards[0].parent_shard_id}'"
      puts "== -- starting hash key = '#{sd.shards[0].hash_key_range.starting_hash_key}'"
      puts "== -- ending hash key = '#{sd.shards[0].hash_key_range.ending_hash_key}'"
      puts "== -- starting sequence number = '#{sd.shards[0].sequence_number_range.starting_sequence_number}'"
      puts "== -- ending sequence number = '#{sd.shards[0].sequence_number_range.ending_sequence_number}'"
      puts "== -- has more shards = '#{sd.has_more_shards}'"
      puts "== -- retention period in hours = '#{sd.retention_period_hours}'"
      puts "== --------------------------------------------------------------"
    end
    puts "== kinesis_list finished"
    puts "== ================================================================"
  end
end
