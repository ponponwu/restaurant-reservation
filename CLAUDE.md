# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Core Commands

### Development Setup
```bash
# Install dependencies
bundle install
npm install

# Database setup
rails db:create db:migrate db:seed

# Start development server
rails server

# Start background jobs (if needed)
bundle exec sidekiq
```

### Testing

#### Fast Test Execution (Optimized)
```bash
# Use optimized test runner for different speeds
bin/rspec-fast               # Fast tests only (models, units) - ~30 seconds
bin/rspec-fast medium        # Medium tests (services, requests) - ~2 minutes  
bin/rspec-fast slow          # Slow tests (system tests) - ~3-5 minutes
bin/rspec-fast all           # All tests - ~5-8 minutes

# Run tests with performance profiling
bundle exec rspec --profile 10     # Show 10 slowest tests
```

#### Standard Test Commands  
```bash
# Run all tests
bundle exec rspec

# Run specific test types
bundle exec rspec spec/models        # Model tests
bundle exec rspec spec/services      # Service tests
bundle exec rspec spec/requests      # Request tests
bundle exec rspec spec/system        # System tests

# Run single test file
bundle exec rspec spec/models/reservation_spec.rb

# Run specific test with line number
bundle exec rspec spec/models/reservation_spec.rb:25

# Test with coverage
COVERAGE=true bundle exec rspec
```

### Code Quality & Linting
```bash
# Run RuboCop
bundle exec rubocop

# Auto-fix RuboCop issues
bundle exec rubocop -a

# Security audit
bundle exec brakeman

# Dependency audit
bundle exec bundle-audit
```

### Redis & Background Services
```bash
# Verify Redis lock service upgrade
RAILS_ENV=test bundle exec rails reservation_lock:verify_upgrade

# Test lock service functionality
RAILS_ENV=test bundle exec rails reservation_lock:test_lock_service

# Check Redis health
bundle exec rails reservation_lock:check_redis
```

### Asset Management
```bash
# Build JavaScript
npm run build

# Build CSS with Tailwind
npm run build:css

# Watch CSS changes
npm run watch:css

# Rails asset precompilation
rails assets:precompile
```

## Architecture Overview

### High-Level System Design
This is a Ruby on Rails 7 restaurant reservation system using Hotwire (Turbo + Stimulus) for modern frontend experiences. The architecture follows a layered approach:

**Frontend Layer**: Hotwire + Tailwind CSS with responsive design
**Controller Layer**: RESTful Rails controllers with strong parameter filtering
**Service Layer**: Business logic encapsulation for complex operations
**Model Layer**: ActiveRecord models with comprehensive validations
**Data Layer**: PostgreSQL with Redis for caching/locking

### Key Service Classes
- **ReservationAllocatorService**: Handles table allocation logic including table combinations
- **EnhancedReservationLockService**: Redis-based concurrent reservation locking
- **AvailabilityService**: Checks table availability across time periods
- **ReservationService**: Core reservation business logic

### Critical Models & Relationships
- **Restaurant** → has many tables, business periods, reservations
- **RestaurantTable** → belongs to restaurant and table_group
- **Reservation** → belongs to restaurant, table (optional), business_period
- **TableCombination** → manages multiple tables for large parties
- **BusinessPeriod** → defines operating hours and rules

### Redis Integration
The system uses Redis for:
- Concurrent reservation locking (EnhancedReservationLockService)
- Cache storage for availability calculations
- Session storage (configurable)

**Important**: The system has a TestRedis mock for test environments that properly handles concurrent operations with mutex locking.

### Authentication & Authorization
- **Devise** for user authentication
- **CanCanCan** for role-based authorization
- Three user roles: admin, manager, staff
- Restaurant-scoped permissions

## Development Conventions

### Model Structure (7-block pattern)
Models follow a strict structure:
1. Associations (belongs_to, has_many, etc.)
2. Validations (presence, format, custom)
3. Scopes (active, for_date, etc.) 
4. Enums (status, type fields)
5. Callbacks (before_save, after_update_commit)
6. Instance methods (public)
7. Private methods

### Service Layer Patterns
Services handle complex business logic:
- Initialize with dependencies
- Public interface methods with error handling
- Use ActiveRecord transactions
- Return standardized result objects
- Comprehensive error logging

### Controller Patterns
- Authentication/authorization checks first
- Strong parameters
- Service object delegation for business logic
- Support both Turbo Stream and HTML responses
- Proper error handling with appropriate HTTP status

### Hotwire Frontend
- Turbo Frames for partial page updates
- Stimulus controllers for interactive behavior
- Turbo Streams for real-time updates
- Progressive enhancement approach

## Testing Approach

### Test Performance Optimization
The test suite has been optimized for speed with the following improvements:

**System Test Optimizations:**
- Reduced Capybara wait times from 10-15s to 5-8s
- Optimized Chrome browser configuration with performance flags
- Added test categorization (fast/medium/slow) for selective execution

**Database Operation Optimizations:**
- Use `build_stubbed` for tests that don't need database persistence
- Optimized factory usage to reduce database hits
- Batch data creation where possible

**Concurrent Test Optimizations:**  
- Reduced sleep times in lock service tests from 1.1s to 0.3s
- Optimized thread synchronization delays from 0.1s to 0.05s
- Enhanced mock usage for non-critical concurrent scenarios

**Expected Performance Gains:**
- Fast tests (models): ~30 seconds
- Medium tests (services/requests): ~2 minutes
- Slow tests (system): ~3-5 minutes  
- Full suite: 50-70% faster execution

### Test Organization
```
spec/
├── models/           # ActiveRecord model tests
├── services/         # Business logic service tests  
├── requests/         # Controller integration tests
├── system/          # Full-stack feature tests
├── factories/       # FactoryBot test data
└── support/         # Test helpers and config
```

### Factory Patterns
Use FactoryBot for test data with traits:
- Basic factories for each model
- Traits for common variations (:confirmed, :cancelled, etc.)
- Association handling between related models

### Service Testing
- Test both success and failure paths
- Mock external dependencies
- Verify transaction rollbacks on errors
- Test concurrent operations for locking services

## Key Configuration Files

### Redis Configuration
`config/initializers/redis.rb` - Configures Redis.current for different environments:
- Test: Uses TestRedis mock with thread safety
- Development/Production: Connects to Redis server with connection pooling

### Environment-Specific Settings
- Test: Uses in-memory cache and TestRedis
- Development: Local PostgreSQL and Redis
- Production: Configured via environment variables

## Business Logic Specifics

### Table Allocation Algorithm
The system supports:
- Single table allocation based on capacity and availability
- Table combination (multiple tables) for large parties
- Table group restrictions (no cross-group combinations)
- Business period isolation (unlimited vs. timed dining)
- Special handling for children (no bar seating)

### Reservation Locking
Uses Redis-based distributed locking:
- Prevents concurrent reservations for same time/table
- Retry mechanism with exponential backoff  
- Automatic lock expiration (30 seconds)
- Thread-safe TestRedis for testing

### Time Zone Handling
- All times stored in UTC
- Restaurant-specific timezone display
- Business period calculations in local time
- Proper DST handling

## Common Debugging

### Test Failures
- Run `bundle exec rspec` to see specific failures
- Check factory definitions if model creation fails
- Verify Redis service is running for lock service tests
- Use `RAILS_ENV=test` for rake tasks

### Redis Issues
- Check Redis connection: `bundle exec rails reservation_lock:check_redis`
- Verify lock service: `bundle exec rails reservation_lock:test_lock_service`
- Clear stuck locks: `bundle exec rails reservation_lock:clear_all_locks`

### Database Issues
- Reset test DB: `RAILS_ENV=test rails db:drop db:create db:migrate`
- Check migrations: `rails db:migrate:status`
- Seed development data: `rails db:seed`

### System Test Browser Issues
If system tests show "Browser not available in test environment":

1. **Check Chrome and ChromeDriver versions compatibility:**
```bash
# Check current versions
/Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome --version
chromedriver --version

# Update ChromeDriver if versions don't match
brew upgrade chromedriver
```

2. **Chrome for Testing vs Regular Chrome:**
   - System may have both "Google Chrome" and "Google Chrome for Testing"
   - Regular Chrome (/Applications/Google Chrome.app) is preferred for newer versions
   - Chrome for Testing (/Applications/Google Chrome for Testing.app) is older
   - Configuration automatically chooses the right version

3. **Browser configuration location:**
   - `spec/support/capybara.rb` - Main Capybara driver setup
   - `spec/support/system_test_helpers.rb` - Browser availability checks
   - Both files use unified `configure_chrome_binary()` method

4. **Environment variable override:**
```bash
# Force specific Chrome binary if needed
export CHROME_BIN="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
bundle exec rspec spec/system
```

## Important Notes

### Security Requirements
- All user inputs must be sanitized and validated
- CSRF protection enabled for all forms
- Role-based access control enforced
- SQL injection protection via ActiveRecord
- XSS protection via Rails auto-escaping

### Performance Considerations
- Use `includes()` to avoid N+1 queries
- Database indexes on frequently queried columns
- Fragment caching for expensive calculations
- Turbo Stream updates minimize full page reloads

### Code Quality Standards
- RuboCop for style enforcement
- Brakeman for security scanning
- 85%+ test coverage requirement
- Comprehensive error handling in services
- Clear, descriptive variable and method names