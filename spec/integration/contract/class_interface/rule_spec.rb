# frozen_string_literal: true

require "dry/validation/contract"

RSpec.describe Dry::Validation::Contract, ".rule" do
  subject(:contract) { contract_class.new }

  let(:contract_class) do
    Class.new(Dry::Validation::Contract) do
      def self.name
        "TestContract"
      end

      params do
        required(:email).filled(:string)
        optional(:login).filled(:string)

        optional(:details).hash do
          optional(:address).hash do
            required(:street).value(:string)
          end
        end
      end
    end
  end

  context "when the name matches one of the keys" do
    before do
      contract_class.rule(:login) do
        key.failure("is too short") if values[:login].size < 3
      end
    end

    it "applies rule when value passed schema checks" do
      expect(contract.(email: "jane@doe.org", login: "ab").errors.to_h)
        .to eql(login: ["is too short"])
    end
  end

  context "when the name does not match one of the keys" do
    before do
      contract_class.rule do
        key(:custom).failure("this works")
      end
    end

    it "applies the rule regardless of the schema result" do
      expect(contract.(email: "jane@doe.org", login: "jane").errors.to_h)
        .to eql(custom: ["this works"])
    end
  end

  context "with a hash as the key identifier" do
    before do
      contract_class.rule(details: {address: :street}) do
        key.failure("cannot be empty") if values[:details][:address][:street].strip.empty?
      end
    end

    it "applies the rule when nested value passed schema checks" do
      expect(contract.(email: "jane@doe.org", login: "jane", details: nil).errors.to_h)
        .to eql(details: ["must be a hash"])

      expect(contract.(email: "jane@doe.org", login: "jane", details: {address: nil}).errors.to_h)
        .to eql(details: {address: ["must be a hash"]})

      expect(contract.(email: "jane@doe.org", login: "jane", details: {address: {street: " "}}).errors.to_h)
        .to eql(details: {address: {street: ["cannot be empty"]}})
    end
  end

  context "with a rule for nested hash and another rule for its member" do
    before do
      contract_class.rule(details: :address) do
        key.failure("invalid no matter what")
      end

      contract_class.rule(details: :address) do
        key.failure("seriously invalid")
      end

      contract_class.rule(details: {address: :street}) do
        key.failure("cannot be empty") if values[:details][:address][:street].strip.empty?
      end

      contract_class.rule(details: {address: :street}) do
        key.failure("must include a number") unless values[:details][:address][:street].match?(/\d+/)
      end
    end

    it "applies the rule when nested value passed schema checks" do
      expect(contract.(email: "jane@doe.org", login: "jane", details: {address: {street: " "}}).errors.to_h)
        .to eql(
          details: {address: [
            ["invalid no matter what", "seriously invalid"],
            {street: ["cannot be empty", "must include a number"]}
          ]}
        )
    end
  end

  context "with a rule that sets a general base error for the whole input" do
    before do
      contract_class.rule do
        key.failure("this whole thing is invalid")
      end
    end

    it "sets a base error not attached to any key" do
      expect(contract.(email: "jane@doe.org", login: "").errors.to_h)
        .to eql(login: ["must be filled"], nil => ["this whole thing is invalid"])

      expect(contract.(email: "jane@doe.org", login: "").errors.filter(:base?).map(&:to_s))
        .to eql(["this whole thing is invalid"])
    end
  end

  context "with a list of keys" do
    before do
      contract_class.rule(:email, :login) do
        if !values[:email].empty? && !values[:login].empty?
          key(:login).failure("is not needed when email is provided")
        end
      end
    end

    it "applies the rule when all values passed schema checks" do
      expect(contract.(email: nil, login: nil).errors.to_h)
        .to eql(email: ["must be filled"], login: ["must be filled"])

      expect(contract.(email: "jane@doe.org", login: "jane").errors.to_h)
        .to eql(login: ["is not needed when email is provided"])
    end
  end

  context "when keys are missing in the schema" do
    it "raises error with a list of symbol keys" do
      expect { contract_class.rule(:invalid, :wrong) }
        .to raise_error(
          Dry::Validation::InvalidKeysError,
          "TestContract.rule specifies keys that are not defined by the schema: [:invalid, :wrong]"
        )
    end

    it "raises error with a hash path" do
      expect { contract_class.rule(invalid: :wrong) }
        .to raise_error(
          Dry::Validation::InvalidKeysError,
          "TestContract.rule specifies keys that are not defined by the schema: [{:invalid=>:wrong}]"
        )
    end

    it "raises error with a dot notation" do
      expect { contract_class.rule("invalid.wrong") }
        .to raise_error(
          Dry::Validation::InvalidKeysError,
          'TestContract.rule specifies keys that are not defined by the schema: ["invalid.wrong"]'
        )
    end

    it "raises error with a hash path with multiple nested keys" do
      expect { contract_class.rule(invalid: %i[wrong not_here]) }
        .to raise_error(
          Dry::Validation::InvalidKeysError,
          'TestContract.rule specifies keys that are not defined by the schema: [{:invalid=>[:wrong, :not_here]}]'
        )
    end
  end

  context 'when schema is nested and reused' do
    let(:contract_class) do
      Class.new(Dry::Validation::Contract) do
        def self.name
          "TestContract"
        end

        UserSchema = Dry::Schema.Params do
          required(:email).filled(:string)
          optional(:login).filled(:string)
          optional(:details).hash do
            optional(:address).hash do
              required(:street).value(:string)
            end
          end
        end

        IdentiferSchema = Dry::Schema.Params do
          required(:external_id).filled(:string)
        end

        UserRequestSchema = Dry::Schema.Params do
          required(:user).hash do
            required(:external_id).filled(:string)
            required(:email).filled(:string)
            optional(:login).filled(:string)
            optional(:details).hash do
              optional(:address).hash do
                required(:street).value(:string)
              end
            end
          end
        end

        params(UserRequestSchema)
      end
    end

    context 'when the rule being applied to a key is in a reused nested schema' do
      let(:request) { { user: { external_id: '12345abc', email: 'jane@doe.org', login: 'ab'} }}

      before do
        contract_class.rule(user: :login) do
          key.failure("is too short") if values[user: :login].size < 3
        end
      end

      it 'applies the rule when passed schema checks' do
        expect(contract.(request).errors.to_h)
          .to eql(user: { login: ["is too short"] })
      end
    end

    context 'when schema has no rules' do
      let(:request) { { user: { external_id: '12345abc', email: 'jane@doe.org' } } }

      it 'validates as successful' do
        expect(contract.(request).success?).to eq true
      end
    end
  end

  context 'when rule being applied to a key from a reused schema' do

  end

  describe "abstract contract" do
    let(:abstract_contract) do
      Class.new(Dry::Validation::Contract) do
        rule do
          base.failure("error from abstract contract")
        end
      end
    end

    let(:contract_class) do
      Class.new(abstract_contract) do
        params do
          required(:name).filled(:string)
        end
      end
    end

    it "applies rules from the parent abstract contract" do
      expect(contract.(name: "").errors.to_h).to eql(
        nil => ["error from abstract contract"], name: ["must be filled"]
      )
    end
  end
end
