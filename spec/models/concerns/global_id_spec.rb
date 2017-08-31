require 'spec_helper'

describe GlobalId, :type => :model do
  describe "global_id" do
    it "should only generate an id of the record is saved" do
      u = User.new
      expect(u.global_id).to eq(nil)
      u.save
      expect(u.global_id).to match(/\d+_\d+/)
    end
  end
  
  describe "finding" do
    it "should find_by_global_id" do
      u = User.create
      expect(User.find_by_global_id(nil)).to eq(nil)
      expect(User.find_by_global_id("")).to eq(nil)
      expect(User.find_by_global_id(u.id.to_s + "_0")).to eq(nil)
      expect(User.find_by_global_id(u.global_id)).to eq(u)
    end
    
    it "should require a nonce for protected classes" do
      i = ButtonImage.create
      expect(ButtonImage.find_by_global_id(nil)).to eq(nil)
      expect(ButtonImage.find_by_global_id("")).to eq(nil)
      expect(ButtonImage.find_by_global_id("1_" + i.id.to_s)).to eq(nil)
      expect(ButtonImage.find_by_global_id("1_" + i.id.to_s + "_" + i.nonce)).to eq(i)
    end
    
    it "should allow a bad or missing nonce for legacy reords" do
      i = ButtonImage.create(:nonce => "legacy")
      expect(i.nonce).to eq('legacy')
      expect(ButtonImage.find_by_global_id(nil)).to eq(nil)
      expect(ButtonImage.find_by_global_id("")).to eq(nil)
      expect(ButtonImage.find_by_global_id("1_" + i.id.to_s)).to eq(i)
      expect(ButtonImage.find_by_global_id("1_" + i.id.to_s + "_" + i.nonce)).to eq(i)
      expect(ButtonImage.find_by_global_id("1_" + i.id.to_s + "_" + "abcdefg")).to eq(i)
    end
    
    it "should find_by_path" do
      u = User.create(:user_name => "bob")
      expect(User.find_by_path(u.user_name)).to eq(u)
      expect(User.find_by_path("bacon")).to eq(nil)
      expect(User.find_by_path(u.global_id)).to eq(u)
      expect(User.find_by_path("0_0")).to eq(nil)
    end
    
    it "should find_all_by_global_id" do
      u1 = User.create
      u2 = User.create
      expect(User.find_all_by_global_id([])).to eq([])
      expect(User.find_all_by_global_id(["0", "1", u1.global_id])).to eq([u1])
      expect(User.find_all_by_global_id([u1.global_id, u2.global_id, u1.id.to_s]).sort).to eq([u1, u2].sort)
    end
    
    it "should require nonces when finding all by global id" do
      i1 = ButtonImage.create
      i2 = ButtonImage.create
      i3 = ButtonImage.create
      expect(ButtonImage.find_all_by_global_id([])).to eq([])
      expect(ButtonImage.find_all_by_global_id([i1.id.to_s, i2.id.to_s, i1.global_id])).to eq([i1])
      expect(ButtonImage.find_all_by_global_id(["1_#{i1.global_id}", "1_#{i2.global_id}", i3.global_id])).to eq([i3])
    end
    
    it "should not required nonces for legacy records when finding all" do
      i1 = ButtonImage.create(:nonce => "legacy")
      i2 = ButtonImage.create(:nonce => "legacy")
      i3 = ButtonImage.create
      expect(ButtonImage.find_all_by_global_id([])).to eq([])
      expect(ButtonImage.find_all_by_global_id([i1.id.to_s, i2.id.to_s, i3.global_id])).to eq([i3])
      expect(ButtonImage.find_all_by_global_id(["1_#{i1.id}", "1_#{i2.id}_q43gag43", "1_#{i3.id}"]).sort.map(&:id)).to eq([i1, i2].sort.map(&:id))
    end
    
    it "should find_all_by_path" do
      u1 = User.create
      u2 = User.create
      expect(User.find_all_by_path([u1.user_name])).to eq([u1])
      expect(User.find_all_by_path([u1.global_id])).to eq([u1])
      expect(User.find_all_by_path([u1.global_id, u2.global_id]).sort_by(&:id)).to eq([u1, u2])
      expect(User.find_all_by_path([u1.user_name, u2.global_id]).sort_by(&:id)).to eq([u1, u2])
      expect(User.find_all_by_path([u1.global_id, u2.user_name]).sort_by(&:id)).to eq([u1, u2])
      expect(User.find_all_by_path([u1.user_name, u2.user_name]).sort_by(&:id)).to eq([u1, u2])
      expect(User.find_all_by_path([u1.user_name, u2.user_name, u1.global_id, "32", u2.global_id]).sort_by(&:id)).to eq([u1, u2])
    end
  end
  
  describe "Board exceptions" do
    it "should find_by_path" do
      b = Board.create(:key => "hat/man")
      expect(b.key).to eq("hat/man")
      expect(Board.find_by_path(b.key)).to eq(b)
      expect(Board.find_by_path("bacon")).to eq(nil)
      expect(Board.find_by_path(b.global_id)).to eq(b)
      expect(Board.find_by_path("0_0")).to eq(nil)
    end

    it "should find_all_by_path" do
      b1 = Board.create(:key => "hat/man")
      b2 = Board.create(:key => "friend/chicken")
      expect(Board.find_all_by_path([b1.key])).to eq([b1])
      expect(Board.find_all_by_path([b1.global_id])).to eq([b1])
      expect(Board.find_all_by_path([b1.global_id, b2.global_id]).sort_by(&:id)).to eq([b1, b2])
      expect(Board.find_all_by_path([b1.key, b2.global_id]).sort_by(&:id)).to eq([b1, b2])
      expect(Board.find_all_by_path([b1.global_id, b2.key]).sort_by(&:id)).to eq([b1, b2])
      expect(Board.find_all_by_path([b1.key, b2.key]).sort_by(&:id)).to eq([b1, b2])
      expect(Board.find_all_by_path([b1.key, b2.key, b1.global_id, "32", b2.global_id]).sort_by(&:id)).to eq([b1, b2])
    end
  end
  
  describe "User exceptions" do
    it "should find_by_path" do
      u = User.create(:user_name => "bob")
      expect(User.find_by_path(u.user_name)).to eq(u)
      expect(User.find_by_path("bacon")).to eq(nil)
      expect(User.find_by_path(u.global_id)).to eq(u)
      expect(User.find_by_path("0_0")).to eq(nil)
    end

    it "should find_all_by_path" do
      u1 = User.create
      u2 = User.create
      expect(User.find_all_by_path([u1.user_name])).to eq([u1])
      expect(User.find_all_by_path([u1.global_id])).to eq([u1])
      expect(User.find_all_by_path([u1.global_id, u2.global_id]).sort_by(&:id)).to eq([u1, u2])
      expect(User.find_all_by_path([u1.user_name, u2.global_id]).sort_by(&:id)).to eq([u1, u2])
      expect(User.find_all_by_path([u1.global_id, u2.user_name]).sort_by(&:id)).to eq([u1, u2])
      expect(User.find_all_by_path([u1.user_name, u2.user_name]).sort_by(&:id)).to eq([u1, u2])
      expect(User.find_all_by_path([u1.user_name, u2.user_name, u1.global_id, "32", u2.global_id]).sort_by(&:id)).to eq([u1, u2])
    end
  end
  
  describe "local_ids" do
    it "should return the correct values" do
      expect(User.local_ids(['1_123112', '2_151412124'])).to eq(['123112', '151412124'])
    end
    
    it "should raise for protected_global_id record types" do
      expect{ButtonSound.local_ids([])}.to raise_error("not allowed for protected record types")
      expect(User.local_ids([])).to eq([])
    end
    
    it "should not map ids that start with non-numbers" do
      expect(User.local_ids(['a1_1', '1_1'])).to eq(['1'])
    end
  end
end
