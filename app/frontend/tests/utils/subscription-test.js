import { describe, it, expect, beforeEach, afterEach, waitsFor, runs, stub } from 'frontend/tests/helpers/jasmine';
import { db_wait } from 'frontend/tests/helpers/ember_helper';
import Subscription from '../../utils/subscription';
import Ember from 'ember';
 
describe('subscription', function() {
  it("should initialize with reasonable values", function() {
    db_wait(function() {
      var s = Subscription.create();
      expect(s.get('user_type')).toEqual('communicator');
      expect(s.get('subscription_type')).toEqual('monthly');
      expect(s.get('subscription_amount')).toEqual('monthly_6');
      expect(s.get('show_options')).toEqual(false);
    });
  });
  
  it("should initialize with the user object if provided", function() {
    db_wait(function() {
      var u = Ember.Object.create({
        subscription: {
          plan_id: 'monthly_6',
          expires: new Date(0)
        },
        email: 'susan@example.com'
      });
      var s = Subscription.create({user: u});
      expect(s.get('user_type')).toEqual('communicator');
      expect(s.get('user_expired')).toEqual(true);
      expect(s.get('subscription_type')).toEqual('monthly');
      expect(s.get('subscription_amount')).toEqual('monthly_6');
      expect(s.get('email')).toEqual('susan@example.com');
    });
  });
  
  it("should reset properly", function() {
    db_wait(function() {
      var s = Subscription.create();
      expect(s.get('user_type')).toEqual('communicator');
      expect(s.get('subscription_type')).toEqual('monthly');
      expect(s.get('subscription_amount')).toEqual('monthly_6');
      expect(s.get('show_options')).toEqual(false);
      s.set('user_type', 'supporter');
      s.set('subscription_type', 'long_term');
      s.reset();
      expect(s.get('user_type')).toEqual('communicator');
      expect(s.get('subscription_type')).toEqual('monthly');
    });
  });
  
  it("should validate plan configurations", function() {
    db_wait(function() {
      var s = Subscription.create();
      s.set('user_type', 'communicator');
      s.set('subscription_type', 'monthly');
      s.set('subscription_amount', 'monthly_2');
      expect(s.get('valid')).toEqual(false);
      s.set('subscription_amount', 'monthly_3');
      expect(s.get('valid')).toEqual(true);
      s.set('subscription_amount', 'monthly_11');
      expect(s.get('valid')).toEqual(false);
      s.set('subscription_amount', 'slp_monthly_3');
      expect(s.get('subscription_amount')).toEqual('monthly_6');
      expect(s.get('valid')).toEqual(true);
      s.set('user_type', 'supporter');
      expect(s.get('subscription_amount')).toEqual('slp_long_term_free');
      s.set('subscription_type', 'monthly');
      s.set('subscription_amount', 'slp_monthly_3');
      expect(s.get('valid')).toEqual(true);
      s.set('subscription_amount', 'slp_monthly_8');
      expect(s.get('valid')).toEqual(false);
      s.set('subscription_amount', 'slp_long_term_free');
      expect(s.get('valid')).toEqual(false);
      s.set('subscription_type', 'long_term');
      expect(s.get('valid')).toEqual(true);
      s.set('subscription_amount', 'slp_long_term_100');
      expect(s.get('valid')).toEqual(true);
      s.set('user_type', 'communicator');
      expect(s.get('subscription_amount')).toEqual('monthly_6');
      expect(s.get('valid')).toEqual(true);
      s.set('subscription_amount', 'long_term_100');
      expect(s.get('valid')).toEqual(true);
    
      s.set('subscription_type', 'gift_code');
      expect(s.get('valid')).toEqual(false);
      s.set('gift_code', 'abcdefg');
      expect(s.get('valid')).toEqual(true);

      s.set('subscription_type', 'long_term_gift');
      expect(s.get('valid')).toEqual(false);
      s.set('email', 'bob@example.com');
      expect(s.get('valid')).toEqual(false);
      s.set('subscription_amount', 'long_term_100');
      expect(s.get('valid')).toEqual(false);
      s.set('subscription_amount', 'long_term_150');
      expect(s.get('valid')).toEqual(true);
      s.set('subscription_amount', 'long_term_custom');
      expect(s.get('valid')).toEqual(false);
      s.set('subscription_custom_amount', '100');
      expect(s.get('valid')).toEqual(false);
      s.set('subscription_custom_amount', '150');
      expect(s.get('valid')).toEqual(true);
      s.set('subscription_custom_amount', '222');
      expect(s.get('valid')).toEqual(false);
      s.set('subscription_custom_amount', '5000');
      expect(s.get('valid')).toEqual(true);
    });
  });
  
  
  it("should process settings and return correct descriptions", function() {
    db_wait(function() {
      var s = Subscription.create();
      s.set('subscription_amount', 'monthly_6');
      expect(s.get('amount_in_cents')).toEqual(600);
      expect(s.get('description')).toEqual("CoughDrop monthly subscription");
      expect(s.get('subscription_plan_description')).toEqual('no plan');
      expect(s.get('purchase_description')).toEqual('Subscribe');

      s.set('subscription_plan', 'monthly_3');
      s.set('subscription_amount', 'slp_long_term_100');
      expect(s.get('subscription_amount')).toEqual('monthly_6');
      expect(s.get('amount_in_cents')).toEqual(600);
    
      s.set('subscription_type', 'long_term');
      s.set('user_type', 'supporter');
      s.set('subscription_amount', 'slp_long_term_100');
      expect(s.get('amount_in_cents')).toEqual(10000);
      expect(s.get('description')).toEqual("CoughDrop supporting-role 5-year purchase");
      expect(s.get('subscription_plan_description')).toEqual('communicator monthly $3');
      expect(s.get('purchase_description')).toEqual('Purchase');
    });
  });
  
  it("should return correct description for free forever plans", function() {
      var s = Subscription.create();
      s.set('subscription_amount', 'monthly_6');
      expect(s.get('amount_in_cents')).toEqual(600);
      expect(s.get('description')).toEqual("CoughDrop monthly subscription");
      expect(s.get('subscription_plan_description')).toEqual('no plan');
      s.set('user', {subscription: {never_expires: true}});
      expect(s.get('subscription_plan_description')).toEqual('free forever');
  });

  it("should initialize the purchasing system", function() {
    db_wait(function() {
      var handler = {};
      var checkout = {
        configure: function(args) {
          handler.args = args;
          return handler;
        }
      };
      console.log('stubbing...');
      stub(document.body, 'appendChild', function() {
        console.log('appending...');
        window.StripeCheckout = checkout;
      });
      var old_key = window.stripe_public_key;
      window.stripe_public_key = 'asdfasdf';
      Subscription.init();
      waitsFor(function() { return Subscription.handler == handler; });
      runs(function() {
        expect(handler.args.key).toEqual('asdfasdf');
        expect(handler.args.image).toEqual('/images/logo-big.png');
        expect(handler.args.token).toNotEqual(undefined);
      
        window.StripeCheckout = null;
        window.stripe_public_key = old_key;
      });
    });
  });

  describe("purchase", function() {
    it("should return a rejected promise if not initialized", function() {
      db_wait(function() {
        stub(window, 'alert', function() { });
        Subscription.handler = null;
        var failed = false;
        var res = Subscription.purchase({});
        res.then(null, function(err) { failed = err; });
        waitsFor(function() { return failed; });
        runs(function() {
          expect(failed.error).toEqual('not ready');
        });
      });
    });
    
    it("should return a valid promise if initialized", function() {
      db_wait(function() {
        var open_args = null;
        var handler = {
          open: function(args) {
            open_args = args;
          }
        };
        var checkout = {};
        window.StripeCheckout = checkout;
        Subscription.handler = handler;
      
        var s = Subscription.create();
        s.set('subscription_amount', 'monthly_6');
        var res = Subscription.purchase(s);
        expect(res.then).toNotEqual(undefined);
        window.StripeCheckout = null;
      });
    });
    
    it("should call the purchasing tool", function() {
      db_wait(function() {
        var open_args = null;
        var handler = {
          open: function(args) {
            open_args = args;
          }
        };
        var checkout = {};
        window.StripeCheckout = checkout;
        Subscription.handler = handler;
      
        var s = Subscription.create();
        s.set('subscription_amount', 'monthly_6');
        var res = Subscription.purchase(s);
        expect(res.then).toNotEqual(undefined);
        expect(open_args).toNotEqual(null);
        expect(open_args.name).toEqual('CoughDrop');
        expect(open_args.description).toEqual('CoughDrop monthly subscription');
        expect(open_args.amount).toEqual(600);
        expect(open_args.panelLabel).toEqual('Subscribe');
        expect(open_args.email).toEqual(undefined);
        expect(open_args.zipCode).toEqual(true);
        window.StripeCheckout = null;
      });
    });
  });
});
