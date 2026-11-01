#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepOffsetAPI_MakeOffsetShape.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <IGESControl_Reader.hxx>
#include <IGESControl_Writer.hxx>
#include <Message_MsgFile.hxx>
#include <Resource_Manager.hxx>
#include <STEPControl_Reader.hxx>
#include <STEPControl_StepModelType.hxx>
#include <STEPControl_Writer.hxx>
#include <StlAPI_Reader.hxx>
#include <StlAPI_Writer.hxx>
#include <TCollection_AsciiString.hxx>
#include <TopAbs_ShapeEnum.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS_Shape.hxx>
#include <gp_Pnt.hxx>

#include <cstdio>
#include <cstdlib>
#include <stdlib.h>

int main()
{
  unsetenv("CSF_STEPUserDefaults");
  Handle(Resource_Manager) aStepResources = new Resource_Manager("STEP");
  TCollection_AsciiString aStepOperation;
  if (aStepResources.IsNull()
   || !aStepResources->IsInitialized()
   || !aStepResources->Find("FromSTEP.exec.op", aStepOperation)
   || aStepOperation != "FixShape")
  {
    return 5;
  }

  if (!Message_MsgFile::LoadFromEnv("CSF_XSMessage", "XSTEP", "us")
   || !Message_MsgFile::HasMsg("XSTEP_1"))
  {
    return 6;
  }

  const TopoDS_Shape aBox1 = BRepPrimAPI_MakeBox(10.0, 20.0, 30.0).Shape();
  const TopoDS_Shape aBox2 = BRepPrimAPI_MakeBox(gp_Pnt(5.0, 0.0, 0.0), 10.0, 20.0, 30.0).Shape();
  const TopoDS_Shape aFused = BRepAlgoAPI_Fuse(aBox1, aBox2).Shape();
  if (aFused.IsNull() || !BRepCheck_Analyzer(aFused).IsValid())
  {
    return 10;
  }

  BRepOffsetAPI_MakeOffsetShape anOffsetBuilder;
  anOffsetBuilder.PerformBySimple(aBox1, 1.0);
  if (!anOffsetBuilder.IsDone() || anOffsetBuilder.Shape().IsNull())
  {
    return 11;
  }

  BRepMesh_IncrementalMesh aMesher(aFused, 0.5);
  if (!aMesher.IsDone())
  {
    return 12;
  }

  const char* aStepPath = "occt-sdk-consumer.step";
  STEPControl_Writer aWriter;
  if (aWriter.Transfer(aFused, STEPControl_AsIs) != IFSelect_RetDone
   || aWriter.Write(aStepPath) != IFSelect_RetDone)
  {
    return 20;
  }

  STEPControl_Reader aReader;
  if (aReader.ReadFile(aStepPath) != IFSelect_RetDone
   || aReader.TransferRoots() <= 0)
  {
    return 30;
  }

  const TopoDS_Shape aRoundTrip = aReader.OneShape();
  std::remove(aStepPath);
  if (aRoundTrip.IsNull() || !BRepCheck_Analyzer(aRoundTrip).IsValid())
  {
    return 40;
  }

  bool hasValidSolid = aRoundTrip.ShapeType() == TopAbs_SOLID;
  for (TopExp_Explorer anExplorer(aRoundTrip, TopAbs_SOLID); anExplorer.More(); anExplorer.Next())
  {
    if (BRepCheck_Analyzer(anExplorer.Current()).IsValid())
    {
      hasValidSolid = true;
      break;
    }
  }
  if (!hasValidSolid)
  {
    return 50;
  }

  const char* anIgesPath = "occt-sdk-consumer.iges";
  IGESControl_Writer anIgesWriter("MM", 1);
  if (!anIgesWriter.AddShape(aFused) || !anIgesWriter.Write(anIgesPath))
  {
    return 60;
  }

  IGESControl_Reader anIgesReader;
  if (anIgesReader.ReadFile(anIgesPath) != IFSelect_RetDone
   || anIgesReader.TransferRoots() <= 0)
  {
    return 61;
  }
  const TopoDS_Shape anIgesRoundTrip = anIgesReader.OneShape();
  std::remove(anIgesPath);
  if (anIgesRoundTrip.IsNull())
  {
    return 62;
  }

  const char* anStlPath = "occt-sdk-consumer.stl";
  StlAPI_Writer aStlWriter;
  if (!aStlWriter.Write(aFused, anStlPath))
  {
    return 70;
  }

  TopoDS_Shape anStlRoundTrip;
  StlAPI_Reader aStlReader;
  if (!aStlReader.Read(anStlRoundTrip, anStlPath))
  {
    return 71;
  }
  std::remove(anStlPath);
  if (anStlRoundTrip.IsNull())
  {
    return 72;
  }

  return 0;
}
