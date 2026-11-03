import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Firebase Product Manager',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepOrange),
        useMaterial3: true,
      ),
      home: const ProductScreen(),
    );
  }
}

class ProductScreen extends StatefulWidget {
  const ProductScreen({super.key});

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  final CollectionReference<Map<String, dynamic>> products = FirebaseFirestore
      .instance
      .collection('products');

  final TextEditingController searchController = TextEditingController();
  final TextEditingController minPriceController = TextEditingController();
  final TextEditingController maxPriceController = TextEditingController();

  String searchQuery = '';
  double? minPrice;
  double? maxPrice;
  String? filterError;

  @override
  void dispose() {
    searchController.dispose();
    minPriceController.dispose();
    maxPriceController.dispose();
    super.dispose();
  }

  void showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  bool isValidProduct(String name, double? price) {
    return name.trim().isNotEmpty &&
        price != null &&
        price.isFinite &&
        price >= 0;
  }

  void applyFilters() {
    final minText = minPriceController.text.trim();
    final maxText = maxPriceController.text.trim();

    final parsedMin = minText.isEmpty ? null : double.tryParse(minText);

    final parsedMax = maxText.isEmpty ? null : double.tryParse(maxText);

    if ((minText.isNotEmpty &&
            (parsedMin == null || !parsedMin.isFinite || parsedMin < 0)) ||
        (maxText.isNotEmpty &&
            (parsedMax == null || !parsedMax.isFinite || parsedMax < 0))) {
      setState(() {
        filterError = 'Enter valid non-negative price bounds.';
      });
      return;
    }

    if (parsedMin != null && parsedMax != null && parsedMin > parsedMax) {
      setState(() {
        filterError = 'Minimum price cannot exceed maximum price.';
      });
      return;
    }

    setState(() {
      minPrice = parsedMin;
      maxPrice = parsedMax;
      filterError = null;
    });

    FocusScope.of(context).unfocus();
  }

  void resetFilters() {
    searchController.clear();
    minPriceController.clear();
    maxPriceController.clear();

    setState(() {
      searchQuery = '';
      minPrice = null;
      maxPrice = null;
      filterError = null;
    });

    FocusScope.of(context).unfocus();
  }

  Future<void> showProductDialog({
    String? documentId,
    String initialName = '',
    double? initialPrice,
  }) async {
    final nameController = TextEditingController(text: initialName);
    final priceController = TextEditingController(
      text: initialPrice?.toStringAsFixed(2) ?? '',
    );

    final isEditing = documentId != null;
    bool isSaving = false;

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (dialogContext, setDialogState) {
              return AlertDialog(
                title: Text(isEditing ? 'Edit Product' : 'Add Product'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Product Name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: priceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Price',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSaving
                        ? null
                        : () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: isSaving
                        ? null
                        : () async {
                            final name = nameController.text.trim();

                            final price = double.tryParse(
                              priceController.text.trim(),
                            );

                            if (!isValidProduct(name, price)) {
                              showMessage(
                                'Enter a valid name and non-negative price.',
                              );
                              return;
                            }

                            setDialogState(() {
                              isSaving = true;
                            });

                            try {
                              final data = <String, dynamic>{
                                'name': name,
                                'price': price!,
                              };

                              if (documentId == null) {
                                await products.add(data);
                              } else {
                                await products.doc(documentId).update(data);
                              }

                              if (!dialogContext.mounted) return;

                              Navigator.pop(dialogContext);

                              showMessage(
                                isEditing
                                    ? 'Product updated successfully.'
                                    : 'Product added successfully.',
                              );
                            } catch (error) {
                              showMessage('Could not save product: $error');

                              if (dialogContext.mounted) {
                                setDialogState(() {
                                  isSaving = false;
                                });
                              }
                            }
                          },
                    child: Text(
                      isSaving
                          ? 'Saving...'
                          : isEditing
                          ? 'Save Changes'
                          : 'Save',
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      nameController.dispose();
      priceController.dispose();
    }
  }

  Future<void> deleteProduct(String documentId, String productName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Product'),
          content: Text('Are you sure you want to delete "$productName"?'),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      await products.doc(documentId).delete();
      showMessage('Product deleted successfully.');
    } catch (error) {
      showMessage('Could not delete product: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Firebase Product Manager'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search Products',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) {
                    setState(() {
                      searchQuery = value.trim().toLowerCase();
                    });
                  },
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: minPriceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Min Price',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: maxPriceController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Max Price',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                if (filterError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      filterError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: applyFilters,
                        child: const Text('Apply Filters'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      onPressed: resetFilters,
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: products.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Error loading products: ${snapshot.error}',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final allDocuments = snapshot.data!.docs;

                if (allDocuments.isEmpty) {
                  return const Center(
                    child: Text(
                      'No products found. Add your first product!',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                final filteredDocuments = allDocuments.where((document) {
                  final data = document.data();

                  final name = (data['name'] ?? '').toString().toLowerCase();

                  final rawPrice = data['price'];
                  final price = rawPrice is num
                      ? rawPrice.toDouble()
                      : double.nan;

                  if (!name.contains(searchQuery)) {
                    return false;
                  }

                  if (!price.isFinite) {
                    return false;
                  }

                  if (minPrice != null && price < minPrice!) {
                    return false;
                  }

                  if (maxPrice != null && price > maxPrice!) {
                    return false;
                  }

                  return true;
                }).toList();

                if (filteredDocuments.isEmpty) {
                  return const Center(
                    child: Text(
                      'No matching products found.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: filteredDocuments.length,
                  itemBuilder: (context, index) {
                    final document = filteredDocuments[index];

                    final data = document.data();

                    final name = data['name']?.toString() ?? 'Unnamed Product';

                    final rawPrice = data['price'];

                    final price = rawPrice is num ? rawPrice.toDouble() : 0.0;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: const Icon(
                          Icons.shopping_bag_outlined,
                          color: Colors.deepOrange,
                        ),
                        title: Text(name),
                        subtitle: Text('Price: \$${price.toStringAsFixed(2)}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit product',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () {
                                showProductDialog(
                                  documentId: document.id,
                                  initialName: name,
                                  initialPrice: price,
                                );
                              },
                            ),
                            IconButton(
                              tooltip: 'Delete product',
                              icon: const Icon(
                                Icons.delete_outline,
                                color: Colors.red,
                              ),
                              onPressed: () {
                                deleteProduct(document.id, name);
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showProductDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Add Product'),
      ),
    );
  }
}
