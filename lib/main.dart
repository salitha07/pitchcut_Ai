import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pitchcut_ai/features/editor/services/editor_project_store.dart';
import 'package:pitchcut_ai/features/editor/video_editor_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: .fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  final EditorProjectStore _projectStore = EditorProjectStore();
  List<String> _projectIds = const [];
  bool _loadingProjects = true;

  @override
  void initState() {
    super.initState();
    _refreshProjects();
  }

  Future<void> _refreshProjects() async {
    try {
      final projectIds = await _projectStore.listProjectIds();
      if (!mounted) return;
      setState(() {
        _projectIds = projectIds;
        _loadingProjects = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingProjects = false);
    }
  }

  Future<void> _openVideoEditor() async {
    try {
      final files = await FilePicker.pickFiles(type: FileType.video);
      if (!mounted || files.isEmpty) return;

      final selectedFile = files.first;
      final path = selectedFile.path;
      if (path == null || path.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not access the selected video.')),
        );
        return;
      }

      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              VideoEditorScreen(videoPath: path, videoName: selectedFile.name),
        ),
      );
      await _refreshProjects();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open the video picker: $error')),
      );
    }
  }

  Future<void> _openSavedProject(String projectId) async {
    final project = await _projectStore.load(projectId);
    if (!mounted) return;
    if (project == null || project.clips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This project has no editable video.')),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => VideoEditorScreen(
          videoPath: projectId,
          videoName: projectId.replaceAll('\\', '/').split('/').last,
        ),
      ),
    );
    await _refreshProjects();
  }

  void _incrementCounter() {
    setState(() {
      // This call to setState tells the Flutter framework that something has
      // changed in this State, which causes it to rerun the build method below
      // so that the display can reflect the updated values. If we changed
      // _counter without calling setState(), then the build method would not be
      // called again, and so nothing would appear to happen.
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
        actions: [
          IconButton(
            tooltip: 'Open video editor',
            onPressed: _openVideoEditor,
            icon: const Icon(Icons.video_library_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('You have pushed the button this many times:'),
          Text('$_counter', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 28),
          Text('Video projects', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          if (_loadingProjects)
            const Center(child: CircularProgressIndicator())
          else if (_projectIds.isEmpty)
            const Text('Open a video to create your first project.')
          else
            for (final projectId in _projectIds)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.video_file_outlined),
                  title: Text(projectId.replaceAll('\\', '/').split('/').last),
                  subtitle: const Text('Tap to continue editing'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openSavedProject(projectId),
                ),
              ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: const Icon(Icons.add),
      ),
    );
  }
}
