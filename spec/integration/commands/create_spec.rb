require 'spec_helper'
require 'dry-struct'

describe 'Commands / Create' do
  include_context 'container'
  include_context 'users and tasks'

  let(:users) { container.commands.users }
  let(:tasks) { container.commands.tasks }

  before do
    module Test
      UserValidator = Class.new do
        ValidationError = Class.new(ROM::CommandError)

        def self.call(params)
          unless params[:name] && params[:email]
            raise ValidationError, ":name and :email are required"
          end
        end
      end
    end

    configuration.relation(:users)
    configuration.relation(:tasks)

    class Test::CreateUser < ROM::Commands::Create[:memory]
      relation :users
      register_as :create
      result :one
      validator Test::UserValidator
    end

    class Test::CreateTask < ROM::Commands::Create[:memory]
      relation :tasks
      register_as :create
      result :one

      def execute(task, user)
        super(task.merge(name: user.to_h[:name]))
      end
    end

    Test::User = Class.new(Dry::Struct) do
      attribute :name, Types::String
      attribute :email, Types::String
    end

    Test::Task = Class.new(Dry::Struct) do
      attribute :name, Types::String
      attribute :title, Types::String
    end

    class Test::UserMapper < ROM::Mapper
      relation :users
      register_as :entity
      model Test::User
      attribute :name
      attribute :email
    end

    class Test::TaskMapper < ROM::Mapper
      relation :tasks
      register_as :entity
      model Test::Task
      attribute :name
      attribute :title
    end

    configuration.register_command(Test::CreateUser, Test::CreateTask)
    configuration.register_mapper(Test::UserMapper, Test::TaskMapper)
  end

  it 'inserts user on successful validation' do
    result = users.try {
      users.create.call(name: 'Piotr', email: 'piotr@solnic.eu')
    }

    expect(result.value).to eql(name: 'Piotr', email: 'piotr@solnic.eu')
  end

  it 'inserts user and associated task when things go well' do
    result = users.try {
      command = users.create.with(name: 'Piotr', email: 'piotr@solnic.eu')
      command >>= tasks.create.with(title: 'Finish command-api')
      command
    }

    expect(result.value).to eql(name: 'Piotr', title: 'Finish command-api')
  end

  it 'returns validation object with errors on failed validation' do
    result = users.try { users.create.call(name: 'Piotr') }

    expect(result.error).to be_instance_of(Test::ValidationError)
    expect(result.error.message).to eql(":name and :email are required")
    expect(container.relations.users.count).to be(2)
  end

  describe '"result" option' do
    it 'returns a single tuple when set to :one' do
      configuration.commands(:users) do
        define(:create_one, type: :create) do
          result :one
        end
      end

      tuple = { name: 'Piotr', email: 'piotr@solnic.eu' }

      result = users.try {
        users.create_one.call(tuple)
      }

      expect(result.value).to eql(tuple)
    end

    it 'allows only valid result types' do
      expect {
        configuration.commands(:users) do
          define(:create_one, type: :create) do
            result :invalid_type
          end
        end
        container
      }.to raise_error(ROM::Options::InvalidOptionValueError)
    end
  end

  describe 'sending result through a mapper' do
    let(:attributes) do
      { name: 'Jane', email: 'jane@doe.org' }
    end

    it 'uses registered mapper to process the result for :one result' do
      command = container.command(:users).as(:entity).create
      result = command[attributes]

      expect(result).to eql(Test::User.new(attributes))
    end

    it 'with two composed commands respects the :result option' do
      mapper_input = nil

      mapper = proc do |tuples|
        mapper_input = tuples
      end

      left = container.command(:users).as(:entity).create.with(
        name: 'Jane', email: 'jane@doe.org'
      )

      right = container.command(:tasks).as(:entity).create.with(
        title: 'Jane task'
      )

      command = left >> right >> mapper

      result = command.call

      task = Test::Task.new(name: 'Jane', title: 'Jane task')

      expect(mapper_input).to eql([task])
      expect(result).to eql(task)
    end

    it 'uses registered mapper to process the result for :many results' do
      configuration.commands(:users) do
        define(:create_many, type: :create)
      end

      command = container.command(:users).as(:entity).create_many
      result = command[attributes]

      expect(result).to eql([Test::User.new(attributes)])
    end
  end
end
