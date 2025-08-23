# Cheeblr: Cannabis Dispensary Management System

A comprehensive full-stack web application for cannabis dispensary inventory, point-of-sale, and transaction management, utilizing PureScript for frontend development with Haskell backend services, all underpinned by a PostgreSQL database infrastructure.

![License](https://img.shields.io/badge/license-MIT-blue.svg)

## 📚 Documentation

Detailed documentation for each component of the system:

- [Nix Development Environment](./Docs/NixDevEnvironment.md) - Setup and configuration of the Nix-based development environment
- [Backend Documentation](./Docs/BackEnd.md) - Haskell backend API and database implementation
- [Frontend Documentation](./Docs/FrontEnd.md) - PureScript frontend application
- [Dependencies](./Docs/Dependencies.md) - List of dependencies
- [To Do list](./Docs/TODO.md) - List of future features and optimizations
- [Security Recommendations](./Docs/SecurityStrategies.md) - Detailed upgrades planned for security and authentication

## 🌟 Features

### Inventory Management
- **Comprehensive Product Tracking**: Maintain detailed cannabis product information including strain data, THC/CBD content, terpenes, and lineage
- **Real-time Inventory Reservations**: Automatic inventory reservation system prevents overselling during concurrent transactions
- **Visual Categorization**: Products are visually distinguished by category and species
- **Flexible Sorting & Filtering**: Organize inventory by various criteria including name, category, quantity, and strain type
- **Complete CRUD Operations**: Support for creating, reading, updating, and deleting inventory items

### Point-of-Sale System
- **Transaction Processing**: Complete POS workflow for creating and finalizing sales transactions with inventory tracking
- **Multiple Payment Methods**: Support for cash, credit, debit, ACH, gift card, and mixed payment options
- **Tax Management**: Automatic calculation of sales and cannabis-specific excise taxes
- **Discount Application**: Apply percentage-based, fixed amount, BOGO, or custom discounts
- **Receipt Generation**: Create formatted transaction receipts with itemized details

### Financial Operations
- **Cash Register Management**: Open/close registers with starting cash and variance tracking
- **Drawer Reconciliation**: End-of-shift reconciliation with automatic variance calculation
- **Transaction Modifications**: Support for void and refund operations with audit trails
- **Payment Processing**: Real-time payment tracking with change calculation for cash transactions
- **Financial Reporting**: Generate daily sales and transaction reports

### Compliance Features
- **Customer Verification**: Age and medical card verification tracking infrastructure
- **Purchase Limit Enforcement**: Monitor and enforce regulatory purchase limits
- **State Reporting**: Generate compliance reports for regulatory requirements
- **Product Labeling**: Generate compliant product labels with required information
- **Audit Trail**: Complete transaction history with modification tracking

## 🔧 Technology Stack

### Frontend
- **PureScript**: Strongly-typed functional programming language that compiles to JavaScript
- **Deku**: Declarative UI library for PureScript with hooks-like functionality
- **FRP**: Functional Reactive Programming for state management through Poll mechanism
- **Type-safe API Client**: Fully typed communication with backend using shared domain types
- **Discrete Money Handling**: Precise currency operations with proper decimal handling

### Backend
- **Haskell**: Pure functional programming language for robust backend services
- **Servant**: Type-level web API library for defining type-safe REST endpoints
- **PostgreSQL Integration**: Direct database interaction with connection pooling
- **Transaction Support**: ACID-compliant transaction processing with rollback capabilities
- **Resource Pooling**: Efficient database connection management

### Database
- **PostgreSQL**: Advanced open-source relational database with transaction support
- **Inventory Reservations**: Dedicated reservation system to prevent double-booking
- **Transaction Tables**: Comprehensive schema for transactions, items, payments, and taxes
- **Register Management**: Persistent register state with opening/closing history

### Development Environment
- **Nix**: Reproducible development environment with all dependencies
- **Cabal**: Haskell build system
- **Spago**: PureScript package manager and build tool
- **PostgreSQL Service**: Integrated database service through NixOS

## 🚀 Getting Started

### Prerequisites

- [Nix package manager](https://nixos.org/download.html) with flakes enabled

### Development Setup

1. Clone the repository:
   ```bash
   git clone <repository-url>
   cd cheeblr
   nix develop
   deploy
   ```   

This will launch the entire setup (PostgreSQL NixOS systemd service and all).

### API Endpoints

The system exposes comprehensive API endpoints for different functional areas:

#### Inventory Endpoints
- `GET /inventory` - Retrieve all inventory items with real-time availability
- `POST /inventory` - Add a new inventory item
- `PUT /inventory` - Update an existing inventory item
- `DELETE /inventory/:sku` - Delete an inventory item
- `GET /inventory/available/:sku` - Check real-time availability
- `POST /inventory/reserve` - Reserve inventory for a transaction
- `DELETE /inventory/release/:id` - Release inventory reservation

#### Transaction Endpoints
- `GET /transaction` - Get all transactions
- `GET /transaction/:id` - Get specific transaction details
- `POST /transaction` - Create a new transaction
- `PUT /transaction/:id` - Update transaction
- `POST /transaction/void/:id` - Void a transaction
- `POST /transaction/refund/:id` - Process a refund
- `POST /transaction/item` - Add item to transaction with reservation
- `DELETE /transaction/item/:id` - Remove item and release reservation
- `POST /transaction/payment` - Add payment to transaction
- `DELETE /transaction/payment/:id` - Remove payment
- `POST /transaction/finalize/:id` - Finalize transaction and commit inventory

#### Register Management
- `GET /register` - Get all registers
- `GET /register/:id` - Get specific register
- `POST /register` - Create new register
- `POST /register/open/:id` - Open a cash register
- `POST /register/close/:id` - Close register with reconciliation

## 🔄 Recent Architecture Updates

### Enhanced Type Safety
- **Explicit Field Naming**: Transaction and TransactionItem types now use prefixed field names for improved clarity:
- All TransactionItem fields prefixed with `transactionItem` (e.g., `transactionItemId`, `transactionItemQuantity`)
- Prevents naming conflicts and improves code maintainability
- Full type safety maintained across frontend-backend communication

### Inventory Reservation System
- **Real-time Availability**: Inventory checks account for both stock and pending reservations
- **Automatic Reservation**: Items are reserved when added to cart, preventing overselling
- **Reservation Release**: Automatic release when items are removed or transactions are cancelled
- **Finalization Process**: Reservations are committed to actual inventory deductions upon transaction completion

## 🔍 Architecture

The application follows a layered architecture with clear separation of concerns:

### Frontend Layers
1. **UI Components**: Deku-based reactive components
- LiveCart for item selection with real-time inventory
- CreateTransaction for complete POS workflow
- Register management interfaces
2. **State Management**: FRP Poll-based reactive state
3. **Service Layer**: Business logic for transactions, inventory, and registers
4. **API Integration**: Type-safe HTTP clients with automatic serialization

### Backend Layers
1. **API Layer**: Servant-based REST API with type-level routing
2. **Server Layer**: Request handlers with business logic
3. **Database Layer**: PostgreSQL integration with connection pooling
4. **Domain Model**: Shared types ensuring frontend-backend consistency

### Database Schema
- **menu_items**: Product catalog with quantities
- **strain_lineage**: Cannabis-specific product attributes
- **transaction**: Transaction records with status tracking
- **transaction_item**: Line items with tax and discount support
- **payment_transaction**: Payment records with multiple methods
- **inventory_reservation**: Real-time inventory locking
- **register**: Cash register state and history

## 📊 Data Flow

1. **Item Selection**: User selects items → Creates reservation → Updates available inventory
2. **Cart Management**: Items added to transaction → Reservations tracked → Real-time totals calculated
3. **Payment Processing**: Payments added → Balance calculated → Transaction status updated
4. **Finalization**: Transaction completed → Inventory committed → Reservations cleared → Receipt generated

## 🔐 Security Considerations

- **Input Validation**: All user inputs validated on both frontend and backend
- **SQL Injection Prevention**: Parameterized queries throughout
- **Type Safety**: Strong typing prevents many common vulnerabilities
- **Audit Trail**: Complete transaction history with modification tracking
- **Access Control**: Foundation for role-based permissions (see Security Strategies doc)

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 🚧 Development Status

### Completed Features
- ✅ Full inventory management system
- ✅ Complete transaction processing workflow
- ✅ Real-time inventory reservation system
- ✅ Multiple payment method support
- ✅ Register opening/closing with reconciliation
- ✅ Tax calculation (sales and cannabis excise)
- ✅ Void and refund operations
- ✅ Receipt generation

### In Progress
- 🔄 Daily financial reporting
- 🔄 Compliance reporting integration
- 🔄 Customer verification system

### Planned
- 📋 User authentication and authorization
- 📋 Advanced reporting and analytics
- 📋 Inventory forecasting
- 📋 Multi-location support
- 📋 Third-party integrations (Metrc, Leafly, etc.)