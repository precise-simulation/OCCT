#include <BRepAlgoAPI_Fuse.hxx>
#include <BRepCheck_Analyzer.hxx>
#include <BRepMesh_IncrementalMesh.hxx>
#include <BRepOffsetAPI_MakeOffsetShape.hxx>
#include <BRepPrimAPI_MakeBox.hxx>
#include <IFSelect_ReturnStatus.hxx>
#include <IGESControl_Reader.hxx>
#include <IGESControl_Writer.hxx>
#include <RWStl.hxx>
#include <STEPControl_Reader.hxx>
#include <STEPControl_StepModelType.hxx>
#include <STEPControl_Writer.hxx>
#include <StlAPI_Writer.hxx>
#include <TopAbs_ShapeEnum.hxx>
#include <TopExp_Explorer.hxx>
#include <TopoDS_Shape.hxx>
#include <gp_Pnt.hxx>

#include <cstdio>

int main()
{
  const TopoDS_Shape aBox1 = BRepPrimAPI_MakeBox(10.0, 20.0, 30.0).Shape();
  const TopoDS_Shape aBox2 = BRepPrimAPI_MakeBox(gp_Pnt(5.0, 0.0, 0.0), 10.0, 20.0, 30.0).Shape();
  const TopoDS_Shape aFused = BRepAlgoAPI_Fuse(aBox1, aBox2).Shape();
  if (aFused.IsNull() || !BRepCheck_Analyzer(aFused).IsValid())
  {
    return 10;
  }

  BRepMesh_IncrementalMesh aMesher(aFused, 0.1);
  if (!aMesher.IsDone())
  {
    return 11;
  }

  BRepOffsetAPI_MakeOffsetShape anOffset;
  anOffset.PerformBySimple(aBox1, 0.05);
  if (!anOffset.IsDone() || anOffset.Shape().IsNull())
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

  const char* anIgesPath = "occt-sdk-consumer.igs";
  IGESControl_Writer anIgesWriter;
  if (!anIgesWriter.AddShape(aFused) || !anIgesWriter.Write(anIgesPath))
  {
    return 60;
  }

  IGESControl_Reader anIgesReader;
  if (anIgesReader.ReadFile(anIgesPath) != IFSelect_RetDone
   || anIgesReader.TransferRoots() <= 0
   || anIgesReader.OneShape().IsNull())
  {
    return 70;
  }
  std::remove(anIgesPath);

  const char* aStlPath = "occt-sdk-consumer.stl";
  StlAPI_Writer aStlWriter;
  if (!aStlWriter.Write(aFused, aStlPath) || RWStl::ReadFile(aStlPath).IsNull())
  {
    return 80;
  }
  std::remove(aStlPath);

  return 0;
}
